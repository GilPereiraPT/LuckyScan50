package com.gilpereira.luckyscan50

import org.junit.Assert.*
import org.junit.Test

class CaptureQualityTest {
    private val paper=PaperOutline(listOf(PaperPoint(.18,.07),PaperPoint(.82,.07),PaperPoint(.82,.93),PaperPoint(.18,.93)))
    private fun frame(motion: Double=0.0, sharpness: Double=120.0, light: Double=190.0,
        outline: PaperOutline?=paper)=CaptureFrame(outline,light,sharpness,motion)
    @Test fun requiresContinuousStabilityBeforeCapture() {
        val gate=CaptureGate()
        for(t in listOf(0L,200L,400L,600L,800L,1000L)) assertFalse(gate.update(t,frame(),3.0,false).ready)
        assertTrue(gate.update(1200,frame(),3.0,false).ready)
    }
    @Test fun oneFrameAfterLongGapCannotCapture() {
        val gate=CaptureGate();gate.update(0,frame(),0.0,false)
        assertFalse(gate.update(1400,frame(),0.0,false).ready)
    }
    @Test fun motionResetsCountdown() {
        val gate=CaptureGate()
        for(t in 0L..1000L step 200)gate.update(t,frame(),0.0,false)
        assertFalse(gate.update(1100,frame(motion=20.0),0.0,false).ready)
        assertFalse(gate.update(1300,frame(),0.0,false).ready)
    }
    @Test fun gyroAndTiltBlockOtherwiseSharpImage() {
        assertFalse(CaptureGate().update(0,frame(),20.0,false).ready)
        assertTrue(CaptureGate().update(0,frame(),20.0,false).message.contains("Incline"))
        assertTrue(CaptureGate().update(0,frame(),0.0,true).message.contains("imóvel"))
    }
    @Test fun missingSensorsStillUseImageQuality() {
        val gate=CaptureGate()
        for(t in 0L..1200L step 200)gate.update(t,frame(),null,false)
        assertTrue(gate.update(1400,frame(),null,false).ready)
    }
    @Test fun blurAndLightingBlockCapture() {
        assertTrue(CaptureGate().update(0,frame(sharpness=2.0),0.0,false).message.contains("focagem"))
        assertTrue(CaptureGate().update(0,frame(light=25.0),0.0,false).message.contains("iluminação"))
    }
    @Test fun clippedOrAbsentPaperBlocksCapture() {
        assertTrue(CaptureGate().update(0,frame(outline=null),0.0,false).message.contains("fundo"))
        val clipped=PaperOutline(listOf(PaperPoint(0.0,.07),PaperPoint(.82,.07),PaperPoint(.82,.93),PaperPoint(0.0,.93)))
        assertTrue(CaptureGate().update(0,frame(outline=clipped),0.0,false).message.contains("completo"))
    }
    @Test fun perspectiveAndRotationAreMeasuredFromPaper() {
        val trapezoid=PaperOutline(listOf(PaperPoint(.35,.07),PaperPoint(.65,.07),PaperPoint(.9,.93),PaperPoint(.1,.93)))
        assertFalse(trapezoid.aligned)
        val rotated=PaperOutline(listOf(PaperPoint(.18,.04),PaperPoint(.82,.15),PaperPoint(.82,.96),PaperPoint(.18,.85)))
        assertFalse(rotated.aligned)
    }
    @Test fun resetAndBackwardClockStartNewCountdown() {
        val gate=CaptureGate()
        for(t in 0L..1200L step 200)gate.update(t,frame(),0.0,false)
        gate.reset();assertFalse(gate.update(1400,frame(),0.0,false).ready)
        assertFalse(gate.update(1000,frame(),0.0,false).ready)
    }
    private fun image(text: Boolean): IntArray {
        val w=240;val h=320
        return IntArray(w*h) { p ->
            val x=p%w;val y=p/w
            if(x in 45..195 && y in 25..295) {
                if(text && x in 60..180 && y in 90..230 && y%18 in 0..3 && x%14<8)20 else 220
            } else 45
        }
    }
    @Test fun detectsBrightPaperOutlineAndPrintedDetail() {
        val detector=CaptureQuality();val data=image(true)
        val first=detector.analyze(data,240,320)
        assertNotNull(first.paper);assertTrue(first.paper!!.framed);assertTrue(first.paper.aligned)
        assertTrue(first.sharpness>40);assertTrue(first.brightness>85)
        assertTrue(first.motion>5.5)
        assertEquals(0.0,detector.analyze(data,240,320).motion,0.001)
    }
    @Test fun blankPaperDoesNotPassSharpnessGate() {
        val quality=CaptureQuality().analyze(image(false),240,320)
        assertTrue(quality.sharpness<40)
    }
    @Test fun noPaperAndWhiteBackgroundDoNotAutoCapture() {
        val detector=CaptureQuality()
        val dark=detector.analyze(IntArray(240*320){30},240,320)
        assertNull(dark.paper)
        val white=detector.analyze(IntArray(240*320){220},240,320)
        assertNotNull(white.paper);assertFalse(white.paper!!.framed)
    }
}
