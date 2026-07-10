import Cocoa

width = 600
height = 400

image = Cocoa.NSImage.alloc().initWithSize_(Cocoa.NSMakeSize(width, height))
image.lockFocus()

# Draw background (gradient from top to bottom)
gradient = Cocoa.NSGradient.alloc().initWithStartingColor_endingColor_(
    Cocoa.NSColor.colorWithCalibratedRed_green_blue_alpha_(0.96, 0.96, 0.98, 1.0),
    Cocoa.NSColor.colorWithCalibratedRed_green_blue_alpha_(0.90, 0.92, 0.95, 1.0)
)
gradient.drawInRect_angle_(Cocoa.NSMakeRect(0, 0, width, height), -90)

# Draw Title
title = "가마지기"
titleFont = Cocoa.NSFont.systemFontOfSize_weight_(48, Cocoa.NSFontWeightBold)
titleAttrs = {Cocoa.NSFontAttributeName: titleFont, Cocoa.NSForegroundColorAttributeName: Cocoa.NSColor.colorWithCalibratedWhite_alpha_(0.2, 1.0)}
Cocoa.NSString.stringWithString_(title).drawAtPoint_withAttributes_(Cocoa.NSMakePoint(40, 310), titleAttrs)

# Draw Subtitle
subtitle = "보카보카 250BT 커피 로스터 프로파일링 앱"
subFont = Cocoa.NSFont.systemFontOfSize_weight_(18, Cocoa.NSFontWeightMedium)
subAttrs = {Cocoa.NSFontAttributeName: subFont, Cocoa.NSForegroundColorAttributeName: Cocoa.NSColor.colorWithCalibratedWhite_alpha_(0.4, 1.0)}
Cocoa.NSString.stringWithString_(subtitle).drawAtPoint_withAttributes_(Cocoa.NSMakePoint(42, 280), subAttrs)

# Draw arrow or indicator
arrowFont = Cocoa.NSFont.systemFontOfSize_weight_(40, Cocoa.NSFontWeightLight)
arrowAttrs = {Cocoa.NSFontAttributeName: arrowFont, Cocoa.NSForegroundColorAttributeName: Cocoa.NSColor.colorWithCalibratedWhite_alpha_(0.6, 1.0)}
Cocoa.NSString.stringWithString_("➜").drawAtPoint_withAttributes_(Cocoa.NSMakePoint(280, 150), arrowAttrs)

image.unlockFocus()

bitmap = Cocoa.NSBitmapImageRep.alloc().initWithData_(image.TIFFRepresentation())
pngData = bitmap.representationUsingType_properties_(Cocoa.NSPNGFileType, None)
pngData.writeToFile_atomically_("dmg_background.png", True)
print("Background generated: dmg_background.png")
