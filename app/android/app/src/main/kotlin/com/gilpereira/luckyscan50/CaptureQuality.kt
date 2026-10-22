package com.gilpereira.luckyscan50

import kotlin.math.*

data class PaperPoint(val x: Double, val y: Double)
data class PaperOutline(val corners: List<PaperPoint>) {
    private fun distance(a: PaperPoint, b: PaperPoint) = hypot(a.x-b.x, a.y-b.y)
    val width get() = (distance(corners[0],corners[1])+distance(corners[3],corners[2]))/2
    val height get() = (distance(corners[0],corners[3])+distance(corners[1],corners[2]))/2
    val roll get() = atan2(corners[1].y-corners[0].y+corners[2].y-corners[3].y,
        corners[1].x-corners[0].x+corners[2].x-corners[3].x)*180/PI
    val perspective get(): Double {
        fun ratio(a: Double,b: Double) = min(a,b)/max(max(a,b),.001)
        return min(ratio(distance(corners[0],corners[1]),distance(corners[3],corners[2])),
            ratio(distance(corners[0],corners[3]),distance(corners[1],corners[2])))
    }
    val framed get() = width >= .42 && height >= .60 &&
        corners.all { it.x in .025.. .975 && it.y in .025.. .975 } &&
        abs(corners.sumOf { it.x }/4-.5) < .13 && abs(corners.sumOf { it.y }/4-.5) < .13
    val aligned get() = abs(roll) <= 4 && perspective >= .82
}
data class CaptureFrame(val paper: PaperOutline?, val brightness: Double,
    val sharpness: Double, val motion: Double)
data class CaptureDecision(val message: String, val ready: Boolean, val progress: Double)

/** All calculations use downsampled upright luminance. No OCR or network calls. */
class CaptureQuality {
    private var previous: IntArray? = null
    fun analyze(gray: IntArray, width: Int, height: Int): CaptureFrame {
        require(width >= 16 && height >= 16 && gray.size == width*height)
        val old = previous
        val motion = if(old == null || old.size != gray.size) 255.0 else
            gray.indices.step(5).map { abs(gray[it]-old[it]) }.average()
        previous = gray.copyOf()
        val histogram = IntArray(256)
        gray.forEach { histogram[it.coerceIn(0,255)]++ }
        val total = gray.size; val sum = gray.sumOf { it.toLong() }
        var weight = 0; var lower = 0L; var best = -1.0; var threshold = 160
        for(i in 0..254) {
            weight += histogram[i]; lower += i.toLong()*histogram[i]
            if(weight == 0 || weight == total) continue
            val variance = weight.toDouble()*(total-weight)*
                (lower.toDouble()/weight-(sum-lower).toDouble()/(total-weight)).pow(2)
            if(variance > best) { best=variance; threshold=i }
        }
        threshold = (threshold+12).coerceIn(100,230)
        val seen = BooleanArray(total); val queue = IntArray(total)
        var largest = IntArray(0)
        for(seed in gray.indices) {
            if(seen[seed] || gray[seed] < threshold) continue
            var head=0; var tail=1; queue[0]=seed; seen[seed]=true
            while(head < tail) {
                val p=queue[head++]; val x=p%width; val y=p/width
                for(direction in 0..3) {
                    val n=when(direction) {
                        0 -> if(x>0)p-1 else -1
                        1 -> if(x<width-1)p+1 else -1
                        2 -> if(y>0)p-width else -1
                        else -> if(y<height-1)p+width else -1
                    }
                    if(n>=0 && !seen[n] && gray[n]>=threshold) { seen[n]=true; queue[tail++]=n }
                }
            }
            if(tail > largest.size) largest=queue.copyOf(tail)
        }
        if(largest.size < total*.15) return CaptureFrame(null,0.0,0.0,motion)
        val tl=largest.minBy { it%width+it/width }
        val tr=largest.maxBy { it%width-it/width }
        val br=largest.maxBy { it%width+it/width }
        val bl=largest.minBy { it%width-it/width }
        val points=listOf(tl,tr,br,bl).map { PaperPoint((it%width).toDouble()/(width-1),(it/width).toDouble()/(height-1)) }
        val paper=PaperOutline(points)
        val minX=(points.minOf { it.x }*width).toInt()+3
        val maxX=(points.maxOf { it.x }*width).toInt()-3
        val minY=(points.minOf { it.y }*height).toInt()+3
        val maxY=(points.maxOf { it.y }*height).toInt()-3
        var count=0; var light=0L; var lap=0.0; var lap2=0.0
        for(y in max(1,minY) until min(height-1,maxY)) {
            for(x in max(1,minX) until min(width-1,maxX)) {
                val p=y*width+x
                val v=(4*gray[p]-gray[p-1]-gray[p+1]-gray[p-width]-gray[p+width]).toDouble()
                count++; light+=gray[p]; lap+=v; lap2+=v*v
            }
        }
        val sharp=if(count==0) 0.0 else max(0.0,lap2/count-(lap/count).pow(2))
        return CaptureFrame(paper,if(count==0)0.0 else light.toDouble()/count,sharp,motion)
    }
    fun reset() { previous=null }
}

/** A single good frame can never trigger capture; interruptions reset the timer. */
class CaptureGate {
    private var since: Long?=null
    private var last: Long?=null
    private var frames=0
    fun reset() { since=null; last=null; frames=0 }
    fun update(now: Long, frame: CaptureFrame, tilt: Double?, sensorMoving: Boolean): CaptureDecision {
        val paper=frame.paper
        val message=when {
            paper==null -> "Enquadre o talão sobre um fundo contrastante"
            !paper.framed -> "Mostre o talão completo dentro da moldura"
            !paper.aligned -> "Alinhe a câmara com os lados do talão"
            tilt!=null && tilt>12 -> "Incline o telemóvel até ficar nivelado"
            sensorMoving || frame.motion>5.5 -> "Mantenha o telemóvel imóvel"
            frame.brightness<85 || frame.brightness>248 -> "Ajuste a iluminação do talão"
            frame.sharpness<40 -> "Aguarde a focagem; aproxime se necessário"
            else -> null
        }
        if(message!=null) { reset(); return CaptureDecision(message,false,0.0) }
        if(last==null || now-last!!>450 || now<last!!) { since=now; frames=0 }
        last=now; frames++
        val progress=((now-(since?:now))/1200.0).coerceIn(0.0,1.0)
        val ready=progress>=1 && frames>=4
        return CaptureDecision(if(ready)"Pronto para fotografar" else "Mantenha imóvel…",ready,progress)
    }
}
