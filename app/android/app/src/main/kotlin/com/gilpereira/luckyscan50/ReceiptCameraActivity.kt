package com.gilpereira.luckyscan50

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.*
import android.hardware.*
import android.os.*
import android.view.*
import android.widget.*
import androidx.camera.core.*
import androidx.camera.core.Camera
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.*
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.*

/** Full-resolution capture, with bounded local analysis of the live preview. */
class ReceiptCameraActivity : Activity(), LifecycleOwner, SensorEventListener {
    private val registry=LifecycleRegistry(this)
    override val lifecycle: Lifecycle get()=registry
    private val executor=Executors.newSingleThreadExecutor()
    private val detector=CaptureQuality()
    private val gate=CaptureGate()
    private lateinit var preview: PreviewView
    private lateinit var overlay: ReceiptOverlay
    private lateinit var status: TextView
    private lateinit var level: TextView
    private lateinit var shutter: Button
    private lateinit var automatic: Switch
    private lateinit var sensors: SensorManager
    private var provider: ProcessCameraProvider?=null
    private var camera: Camera?=null
    private var capture: ImageCapture?=null
    private var tilt: Double?=null
    private var gravityAt=0L
    private var gyroAt=0L
    private var rotationSpeed=0.0
    private var gravity=DoubleArray(3)
    private var resumed=false
    private var capturing=false
    private var latestReady=false
    private var latestAt=0L
    private var analyzedAt=0L
    private var focusAfter=0L
    private var pendingFile: File?=null
    private var generation=0
    private val gold=Color.rgb(232,201,126)

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        registry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.statusBarColor=Color.rgb(12,22,36)
        window.navigationBarColor=Color.rgb(12,22,36)
        sensors=getSystemService(SENSOR_SERVICE) as SensorManager
        val root=LinearLayout(this).apply {
            orientation=LinearLayout.VERTICAL; setBackgroundColor(Color.rgb(12,22,36))
            fitsSystemWindows=true
        }
        val title=LinearLayout(this).apply { gravity=Gravity.CENTER_VERTICAL; setPadding(dp(12),dp(8),dp(12),dp(8)) }
        title.addView(Button(this).apply { text="Fechar"; setOnClickListener { finish() } })
        title.addView(TextView(this).apply { text="Fotografar boletim"; textSize=20f; setTextColor(gold); setPadding(dp(12),0,0,0) })
        root.addView(title)
        val viewer=FrameLayout(this)
        preview=PreviewView(this).apply {
            implementationMode=PreviewView.ImplementationMode.COMPATIBLE
            scaleType=PreviewView.ScaleType.FIT_CENTER
        }
        viewer.addView(preview,FrameLayout.LayoutParams(-1,-1))
        overlay=ReceiptOverlay(this)
        viewer.addView(overlay,FrameLayout.LayoutParams(-1,-1))
        root.addView(viewer,LinearLayout.LayoutParams(-1,0,1f))
        val panel=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; setPadding(dp(20),dp(8),dp(20),dp(12)) }
        panel.addView(TextView(this).apply {
            text="Coloque o talão numa superfície plana, com todos os lados visíveis. Toque na imagem para focar. Pode fotografar a qualquer momento com o botão."
            setTextColor(Color.LTGRAY); textSize=14f
        })
        level=TextView(this).apply { text="A medir inclinação…"; setTextColor(gold); textSize=15f }
        panel.addView(level)
        status=TextView(this).apply { text="A iniciar a câmara…"; textSize=18f; setTextColor(Color.WHITE); setPadding(0,dp(8),0,dp(8)) }
        panel.addView(status)
        automatic=Switch(this).apply { text="Captura automática quando estiver pronto"; isChecked=true; setTextColor(Color.WHITE) }
        panel.addView(automatic)
        shutter=Button(this).apply {
            text="Fotografar"; isEnabled=false
            setOnClickListener { takePhoto(manual=true) }
        }
        panel.addView(shutter,LinearLayout.LayoutParams(-1,dp(54)))
        root.addView(panel)
        setContentView(root)
        preview.setOnTouchListener { _,event ->
            if(event.action==MotionEvent.ACTION_UP) { focus(event.x,event.y); preview.performClick() }
            true
        }
        if(checkSelfPermission(Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED) startCamera()
        else requestPermissions(arrayOf(Manifest.permission.CAMERA),701)
    }
    private fun dp(value: Int)=(value*resources.displayMetrics.density).toInt()
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code,permissions,results)
        if(code==701) {
            if(results.firstOrNull()==PackageManager.PERMISSION_GRANTED) startCamera()
            else {
                setResult(RESULT_FIRST_USER,Intent().putExtra("error","camera_permission"))
                android.app.AlertDialog.Builder(this)
                    .setTitle("Acesso à câmara")
                    .setMessage("Autorize a câmara nas definições do LuckyScan50 para fotografar. Pode continuar a importar imagens da galeria.")
                    .setPositiveButton("Definições") { _,_ ->
                        startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            android.net.Uri.parse("package:$packageName")))
                        finish()
                    }
                    .setNegativeButton("Voltar") { _,_ -> finish() }
                    .setOnCancelListener { finish() }.show()
            }
        }
    }
    private fun startCamera() {
        val future=ProcessCameraProvider.getInstance(this)
        future.addListener({
            if(isFinishing || isDestroyed) return@addListener
            try {
                val p=future.get(); provider=p
                val rotation=preview.display?.rotation?:Surface.ROTATION_0
                val live=Preview.Builder().setTargetAspectRatio(AspectRatio.RATIO_4_3).setTargetRotation(rotation).build()
                live.setSurfaceProvider(preview.surfaceProvider)
                val shot=ImageCapture.Builder().setTargetAspectRatio(AspectRatio.RATIO_4_3).setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
                    .setTargetRotation(rotation).build()
                capture=shot
                @Suppress("DEPRECATION")
                val analysis=ImageAnalysis.Builder().setTargetResolution(android.util.Size(640,480))
                    .setTargetRotation(rotation).setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                analysis.setAnalyzer(executor) { image -> analyze(image) }
                camera=p.bindToLifecycle(this,CameraSelector.DEFAULT_BACK_CAMERA,live,shot,analysis)
                updateShutter()
                preview.postDelayed({ if(resumed) focus(preview.width/2f,preview.height/2f) },500)
            } catch(error: Exception) {
                status.text="Não foi possível abrir a câmara. Volte atrás e tente novamente."
            }
        },ContextCompat.getMainExecutor(this))
    }
    private fun focus(x: Float,y: Float) {
        if(capturing || camera==null) return
        latestReady=false; gate.reset(); updateShutter()
        focusAfter=SystemClock.elapsedRealtime()+900
        val point=preview.meteringPointFactory.createPoint(x,y)
        try {
            camera?.cameraControl?.startFocusAndMetering(FocusMeteringAction.Builder(point)
                .setAutoCancelDuration(3,TimeUnit.SECONDS).build())
        } catch(_: Exception) { /* Continuous focus remains active. */ }
    }
    private fun analyze(image: ImageProxy) {
        try {
            val now=SystemClock.elapsedRealtime()
            if(now-analyzedAt<180) return
            analyzedAt=now
            val rotation=image.imageInfo.rotationDegrees
            val sourceW=image.width; val sourceH=image.height
            val uprightW=if(rotation%180==0)sourceW else sourceH
            val uprightH=if(rotation%180==0)sourceH else sourceW
            val w=240; val h=(uprightH.toDouble()/uprightW*w).roundToInt().coerceAtLeast(16)
            val plane=image.planes[0]; val buffer=plane.buffer
            val gray=IntArray(w*h)
            for(y in 0 until h) for(x in 0 until w) {
                val ux=(x.toLong()*uprightW/w).toInt().coerceIn(0,uprightW-1)
                val uy=(y.toLong()*uprightH/h).toInt().coerceIn(0,uprightH-1)
                val sx: Int; val sy: Int
                when(rotation) {
                    90 -> { sx=uy; sy=sourceH-1-ux }
                    180 -> { sx=sourceW-1-ux; sy=sourceH-1-uy }
                    270 -> { sx=sourceW-1-uy; sy=ux }
                    else -> { sx=ux; sy=uy }
                }
                gray[y*w+x]=buffer.get(sy*plane.rowStride+sx*plane.pixelStride).toInt() and 255
            }
            val quality=detector.analyze(gray,w,h)
            runOnUiThread {
                if(!resumed || capturing || isFinishing) return@runOnUiThread
                val current=SystemClock.elapsedRealtime()
                val sensorTilt=if(current-gravityAt<=1200)tilt else null
                val moving=current-gyroAt<=1200 && rotationSpeed>.08
                if(current-now>400) { gate.reset(); latestReady=false; updateShutter(); return@runOnUiThread }
                val decision=gate.update(current,quality,sensorTilt,moving || current<focusAfter)
                latestAt=current; latestReady=decision.ready
                updateShutter()
                status.text=decision.message
                status.setTextColor(if(decision.ready)Color.rgb(100,230,150) else Color.WHITE)
                level.text=if(sensorTilt==null)"Nível indisponível · alinhe pela moldura" else
                    "Inclinação: ${sensorTilt.roundToInt()}° · objetivo até 12°"
                overlay.update(quality.paper,w.toFloat()/h,decision.progress,decision.ready,sensorTilt)
                if(decision.ready && automatic.isChecked) takePhoto()
            }
        } catch(_: Exception) {
            runOnUiThread { gate.reset(); latestReady=false; updateShutter() }
        } finally { image.close() }
    }
    private fun updateShutter() {
        shutter.isEnabled=resumed && !capturing && camera!=null && capture!=null
    }
    private fun takePhoto(manual: Boolean=false) {
        val now=SystemClock.elapsedRealtime()
        if(!resumed || capturing) return
        if(!manual && (!latestReady || now-latestAt>400 ||
            (now-gravityAt<=1200 && (tilt?:0.0)>12) ||
            (now-gyroAt<=1200 && rotationSpeed>.08))) return
        val shot=capture?:return
        val token=generation
        capturing=true; latestReady=false; shutter.isEnabled=false
        status.text="A fotografar…"; preview.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
        val file=File(cacheDir,"receipt-camera-${UUID.randomUUID()}.jpg"); pendingFile=file
        shot.takePicture(ImageCapture.OutputFileOptions.Builder(file).build(),
            ContextCompat.getMainExecutor(this),object: ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    if(token!=generation || !resumed || isFinishing || isDestroyed) {
                        file.delete(); pendingFile=null; capturing=false; gate.reset(); return
                    }
                    pendingFile=null
                    setResult(RESULT_OK,Intent().putExtra("path",file.path)); finish()
                }
                override fun onError(error: ImageCaptureException) {
                    file.delete(); pendingFile=null; capturing=false; gate.reset(); updateShutter()
                    status.text="Não foi possível fotografar. Mantenha imóvel e tente novamente."
                }
            })
    }
    override fun onSensorChanged(event: SensorEvent) {
        val now=SystemClock.elapsedRealtime()
        when(event.sensor.type) {
            Sensor.TYPE_GRAVITY,Sensor.TYPE_ACCELEROMETER -> {
                val alpha=if(event.sensor.type==Sensor.TYPE_GRAVITY || gravityAt==0L)0.0 else .85
                for(i in 0..2)gravity[i]=alpha*gravity[i]+(1-alpha)*event.values[i]
                val length=sqrt(gravity.sumOf { it*it })
                if(length>1)tilt=acos((abs(gravity[2])/length).coerceIn(0.0,1.0))*180/PI
                gravityAt=now
            }
            Sensor.TYPE_GYROSCOPE -> { rotationSpeed=sqrt(event.values.sumOf { it.toDouble()*it }); gyroAt=now }
        }
        if((tilt?:0.0)>12 || (now-gyroAt<=1200 && rotationSpeed>.08)) {
            gate.reset(); latestReady=false; updateShutter()
        }
    }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    override fun onStart() { super.onStart(); registry.handleLifecycleEvent(Lifecycle.Event.ON_START) }
    override fun onResume() {
        super.onResume(); registry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)
        resumed=true; gate.reset(); latestReady=false; gravityAt=0; gyroAt=0
        updateShutter()
        val gravitySensor=sensors.getDefaultSensor(Sensor.TYPE_GRAVITY)
        val sensor=gravitySensor?:sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if(sensor!=null)sensors.registerListener(this,sensor,SensorManager.SENSOR_DELAY_UI)
        sensors.getDefaultSensor(Sensor.TYPE_GYROSCOPE)?.let { sensors.registerListener(this,it,SensorManager.SENSOR_DELAY_UI) }
    }
    override fun onPause() {
        resumed=false; generation++; latestReady=false; gate.reset(); sensors.unregisterListener(this)
        shutter.isEnabled=false; registry.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE); super.onPause()
    }
    override fun onStop() { registry.handleLifecycleEvent(Lifecycle.Event.ON_STOP); super.onStop() }
    override fun onDestroy() {
        registry.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
        provider?.unbindAll(); executor.shutdown(); pendingFile?.delete()
        super.onDestroy()
    }
}

private class ReceiptOverlay(context: android.content.Context): View(context) {
    private val paint=Paint(Paint.ANTI_ALIAS_FLAG)
    private var paper: PaperOutline?=null
    private var aspect=.75f
    private var progress=0.0
    private var ready=false
    private var tilt: Double?=null
    fun update(value: PaperOutline?, ratio: Float, amount: Double, good: Boolean, level: Double?) {
        paper=value; aspect=ratio; progress=amount; ready=good; tilt=level; invalidate()
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val imageW=min(width.toFloat(),height*aspect); val imageH=imageW/aspect
        val left=(width-imageW)/2; val top=(height-imageH)/2
        paint.style=Paint.Style.STROKE; paint.strokeWidth=3*resources.displayMetrics.density
        paint.color=if(ready)Color.rgb(100,230,150) else Color.rgb(232,201,126)
        val corners=paper?.corners?:listOf(PaperPoint(.15,.06),PaperPoint(.85,.06),PaperPoint(.85,.94),PaperPoint(.15,.94))
        val path=Path()
        corners.forEachIndexed { i,p -> if(i==0)path.moveTo(left+(p.x*imageW).toFloat(),top+(p.y*imageH).toFloat()) else path.lineTo(left+(p.x*imageW).toFloat(),top+(p.y*imageH).toFloat()) }
        path.close(); canvas.drawPath(path,paint)
        val cx=width/2f; val cy=height/2f; val radius=22*resources.displayMetrics.density
        paint.color=Color.WHITE; paint.strokeWidth=2*resources.displayMetrics.density
        canvas.drawCircle(cx,cy,radius,paint)
        paint.color=if((tilt?:90.0)<=12)Color.rgb(100,230,150) else Color.rgb(232,201,126)
        paint.style=Paint.Style.FILL
        val offset=((tilt?:0.0)/45).coerceIn(0.0,1.0).toFloat()*radius
        canvas.drawCircle(cx,cy+offset,6*resources.displayMetrics.density,paint)
        paint.style=Paint.Style.STROKE; paint.strokeWidth=5*resources.displayMetrics.density
        canvas.drawArc(RectF(cx-radius-8,cy-radius-8,cx+radius+8,cy+radius+8),-90f,(progress*360).toFloat(),false,paint)
    }
}
