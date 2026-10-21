package com.gilpereira.luckyscan50

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodChannel

class ReceiptCameraBridge(private val activity: Activity) {
    private var pending: MethodChannel.Result?=null
    private val requestCode=7041
    @Suppress("DEPRECATION")
    fun open(result: MethodChannel.Result) {
        if(pending!=null) { result.error("camera_busy","A câmara já está aberta.",null); return }
        pending=result
        try { activity.startActivityForResult(Intent(activity,ReceiptCameraActivity::class.java),requestCode) }
        catch(_: Exception) { pending=null; result.error("camera_unavailable","Não foi possível abrir a câmara.",null) }
    }
    fun activityResult(code: Int,status: Int,data: Intent?) {
        if(code!=requestCode)return
        val result=pending?:return; pending=null
        when(status) {
            Activity.RESULT_OK -> result.success(data?.getStringExtra("path"))
            Activity.RESULT_FIRST_USER -> result.error("camera_permission","Autorize a câmara nas definições da aplicação para fotografar.",null)
            else -> result.success(null)
        }
    }
    fun dispose() { pending?.success(null); pending=null }
}
