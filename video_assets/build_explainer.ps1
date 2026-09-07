$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$assetDir = Join-Path $root 'video_assets'
$pptxPath = Join-Path $root 'Logic_Legends_Explainer.pptx'
$videoPath = Join-Path $root 'Logic_Legends_Explainer.mp4'

$slides = @(
    @{ Title='LOGIC LEGENDS'; Subtitle='Accessible understanding through a phone camera'; Narration='Logic Legends is an audio first phone assistant designed for blind and low vision people. It helps users hear what is in front of them and understand printed information without depending on sight.'; Seconds=10; Accent=0x32D5FF },
    @{ Title='THE PROBLEM'; Subtitle='Private information should not require another person'; Narration='Medicine labels, bills, and official notices often force a blind person to ask someone else what they say. That reduces privacy and independence, and a simple transcription may still leave the meaning unclear.'; Seconds=14; Accent=0xFFB84D },
    @{ Title='EYES-FREE BY DESIGN'; Subtitle='Tap or Volume Up: capture   |   Swipe: change mode   |   Volume Down: repeat'; Narration='Logic Legends uses large, location independent controls. Tap anywhere or press Volume Up to capture. Swipe to change mode with spoken confirmation. Press Volume Down to repeat the last important answer.'; Seconds=14; Accent=0x71E6A2 },
    @{ Title='READ & EXPLAIN'; Subtitle='On-device OCR first. Plain-language explanation second.'; Narration='Read and Explain first runs optical character recognition on the phone and speaks captured text. A cloud prototype then explains the text in plain language. High stakes details that cannot be confirmed must be checked with a trusted person or professional.'; Seconds=16; Accent=0xB89CFF },
    @{ Title='EXPLORE'; Subtitle='Camera scene to Gemini cloud prototype to spoken description'; Narration='Explore sends a non sensitive camera image to Gemini and speaks a concise scene description. The app distinguishes setup, quota, service, photo, and connection failures, giving the user a useful recovery step.'; Seconds=14; Accent=0x67C7FF },
    @{ Title='VOICE CHAT'; Subtitle='Experimental third swipe mode with spoken answers'; Narration='Voice Chat is an experimental third swipe mode. It listens for an English question, sends the recognized text to the assistant, reads the answer aloud, and offers touch and spoken recovery paths.'; Seconds=12; Accent=0xFF79B0 },
    @{ Title='COMPREHENSION. CONFIDENCE. RECOVERY.'; Subtitle='Built for the iQOO Hackathon 2026 • Smart Living'; Narration='Logic Legends turns a phone camera into accessible understanding. Hear what is there, understand what it means, and recover without needing to see the screen. This is our cloud connected prototype for the iQOO Hackathon.'; Seconds=12; Accent=0x32D5FF }
)

function Add-TextBox($slide, $text, $left, $top, $width, $height, $size, $color, $bold, $align) {
    $shape = $slide.Shapes.AddTextbox(1, $left, $top, $width, $height)
    $shape.TextFrame.TextRange.Text = $text
    $shape.TextFrame.TextRange.Font.Name = 'Aptos Display'
    $shape.TextFrame.TextRange.Font.Size = $size
    $shape.TextFrame.TextRange.Font.Bold = if ($bold) { -1 } else { 0 }
    $shape.TextFrame.TextRange.Font.Color.RGB = $color
    $shape.TextFrame.TextRange.ParagraphFormat.Alignment = $align
    $shape.TextFrame.WordWrap = -1
    return $shape
}

$powerPoint = New-Object -ComObject PowerPoint.Application
$powerPoint.Visible = -1
$presentation = $powerPoint.Presentations.Add()
$presentation.PageSetup.SlideSize = 15

try {
    $index = 0
    foreach ($item in $slides) {
        $index++
        $slide = $presentation.Slides.Add($index, 12)
        $slide.FollowMasterBackground = 0
        $slide.Background.Fill.ForeColor.RGB = 0x17120F

        $bar = $slide.Shapes.AddShape(1, 0, 0, 960, 18)
        $bar.Fill.ForeColor.RGB = $item.Accent
        $bar.Line.Visible = 0

        $circle = $slide.Shapes.AddShape(9, 740, 70, 150, 150)
        $circle.Fill.ForeColor.RGB = $item.Accent
        $circle.Fill.Transparency = 12
        $circle.Line.Visible = 0
        Add-TextBox $slide 'AI' 765 100 100 70 34 0x17120F $true 2 | Out-Null

        Add-TextBox $slide $item.Title 70 125 800 120 34 0xFFFFFF $true 1 | Out-Null
        Add-TextBox $slide $item.Subtitle 72 260 800 130 22 $item.Accent $false 1 | Out-Null
        Add-TextBox $slide ("0{0}  /  07" -f $index) 72 470 170 35 13 0xB8B8B8 $false 1 | Out-Null
        Add-TextBox $slide 'iQOO HACKATHON 2026  |  SMART LIVING' 550 470 340 35 11 0xB8B8B8 $false 3 | Out-Null

        $wavPath = Join-Path $assetDir ("narration_{0}.wav" -f $index)
        $stream = New-Object -ComObject SAPI.SpFileStream
        $stream.Open($wavPath, 3, $false)
        $voice = New-Object -ComObject SAPI.SpVoice
        $voice.Rate = 0
        $voice.Volume = 100
        $voice.AudioOutputStream = $stream
        [void]$voice.Speak($item.Narration)
        $stream.Close()

        $audio = $slide.Shapes.AddMediaObject2($wavPath, 0, -1, 0, 0, 1, 1)
        $audio.AnimationSettings.PlaySettings.PlayOnEntry = -1
        $audio.AnimationSettings.PlaySettings.HideWhileNotPlaying = -1
        $slide.SlideShowTransition.AdvanceOnTime = -1
        $slide.SlideShowTransition.AdvanceTime = $item.Seconds
    }

    $presentation.SaveAs($pptxPath)
    $presentation.CreateVideo($videoPath, $true, 5, 1080, 30, 85)
    while ($presentation.CreateVideoStatus -eq 1) {
        Start-Sleep -Seconds 5
    }
    if ($presentation.CreateVideoStatus -ne 3) {
        throw "PowerPoint video export failed with status $($presentation.CreateVideoStatus)"
    }
}
finally {
    $presentation.Close()
    $powerPoint.Quit()
    [Runtime.InteropServices.Marshal]::ReleaseComObject($presentation) | Out-Null
    [Runtime.InteropServices.Marshal]::ReleaseComObject($powerPoint) | Out-Null
}

Get-Item $pptxPath, $videoPath | Select-Object FullName, Length
