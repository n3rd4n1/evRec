/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2013 Billy Millare
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

/*
 * AppDelegate.m
 *
 *  Created on: Oct 03, 2013
 *      Author: Billy
 */

#import "AppDelegate.h"
#import <pthread.h>
#import <Security/Security.h>
#import <QuartzCore/QuartzCore.h>

// Captured Events Table View **************************************************

@protocol CapturedEventsTableViewDelegate <NSObject>
- (void)capturedEventsTableView:(NSTableView *)tableView showMoreInfoForRow:(NSInteger)row;
- (void)capturedEventsTableView:(NSTableView *)tableView toggleSelectionForRows:(NSIndexSet *)rows;
@end

@interface CapturedEventsTableView : NSTableView
@end

@implementation CapturedEventsTableView

- (void)awakeFromNib
{
    self.doubleAction = @selector(showMoreInfo);
}

- (void)showMoreInfo
{
    if(self.clickedRow >= 0)
        [self showMoreInfo_];
}

- (void)showMoreInfo_
{
    if(self.selectedRowIndexes.count == 1 && [self.delegate respondsToSelector:@selector(capturedEventsTableView:showMoreInfoForRow:)])
        [(id)self.delegate capturedEventsTableView:self showMoreInfoForRow:self.selectedRow];
}

- (void)toggleSelection
{
    if(self.selectedRowIndexes.count > 0 && [self.delegate respondsToSelector:@selector(capturedEventsTableView:toggleSelectionForRows:)])
        [(id)self.delegate capturedEventsTableView:self toggleSelectionForRows:self.selectedRowIndexes];
}

- (void)keyDown:(NSEvent *)theEvent
{
    if(theEvent.characters.length == 1)
    {
        switch(*theEvent.characters.UTF8String)
        {
            case '\r':
            case '\n':
                [self showMoreInfo_];
                return;
                
            case ' ':
                [self toggleSelection];
                return;
                
            default:
                break;
        }
    }
    
    [super keyDown:theEvent];
}

@end

// Event Bytes Search Field Formatter ******************************************
// Validates search token to be of (hexadecimal) format: "xx xx xx ... xx"

@interface EventBytesSearchFieldFormatter : NSFormatter
@end

@implementation EventBytesSearchFieldFormatter

- (NSString *)stringForObjectValue:(id)obj
{
    return obj;
}

- (BOOL)getObjectValue:(out id *)obj forString:(NSString *)string errorDescription:(out NSString **)error
{
    *obj = string;
    return YES;
}

- (BOOL)isPartialStringValid:(NSString *)partialString newEditingString:(NSString **)newString errorDescription:(NSString **)error
{
    if(partialString.length > 0)
    {
        partialString = [partialString stringByReplacingOccurrencesOfString:@" " withString:@""];
        NSScanner *scanner = [NSScanner scannerWithString:partialString];
        [scanner scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"1234567890abcdefABCDEF"] intoString:NULL];
        
        if(scanner.isAtEnd)
        {
            *newString = [NSMutableString stringWithCapacity:(partialString.length * 3 / 2)];
            
            for(int i = 0 ; i < partialString.length; i += 2)
                [(NSMutableString *)*newString appendFormat:@"%@ ", [partialString substringWithRange:NSMakeRange(i, ((i + 2) > partialString.length) ? 1 : 2)]];
            
            [(NSMutableString *)*newString deleteCharactersInRange:NSMakeRange([*newString length] - 1, 1)];
        }
        
        return NO;
    }
    
    return YES;
}

@end

// AppDelegate *****************************************************************

typedef struct {
    pthread_t ID;
    BOOL isRunning;
    NSAutoreleasePool *autoreleasePool;
    AppDelegate *appDelegate;
} EventPlaybackThreadData;

@interface AppDelegate ()
    <NSWindowDelegate,
        NSTokenFieldDelegate,
        NSTableViewDataSource,
        NSTableViewDelegate,
        CapturedEventsTableViewDelegate,
        NSSplitViewDelegate,
        NSTextViewDelegate,
        NSTextFieldDelegate>
{
    IBOutlet NSButton *authorizeButton;
    IBOutlet NSMenuItem *openMenuItem;
    IBOutlet NSMenuItem *saveMenuItem;
    IBOutlet NSMenuItem *findMenuItem;
    
    IBOutlet NSButton *eventCaptureButton;
    IBOutlet NSBox *eventsFilterBox;
    IBOutlet NSButton *eventsFilterModeToggleButton;
    IBOutlet NSTokenField *eventsFilterTokenField;
    
    IBOutlet NSPanel *capturedEventsPanel;
    IBOutlet NSButton *capturedEventsPanelCloseButton;
    IBOutlet NSButton *capturedEventsPlaybackButton;
    
    IBOutlet NSButton *numberOfCapturedEventsLabel;
    IBOutlet NSScrollView *capturedEventsBasicInfoScrollView;
    IBOutlet NSTableView *capturedEventsBasicInfoTableView;
    IBOutlet NSScrollView *capturedEventsMoreInfoScrollView;
    IBOutlet NSTableView *capturedEventsMoreInfoTableView;

    IBOutlet NSTextField *eventByteNumberTextField;
    IBOutlet NSStepper *eventByteNumberStepper;
    IBOutlet NSTextField *eventSizeLabel;
    IBOutlet NSTextView *eventBytesTextView;
    IBOutlet NSButton *eventNumberButton;
    IBOutlet NSSearchField *eventBytesSearchField;
    
    NSDictionary *eventFieldsDictionary;
    NSDictionary *knownEventsDictionary;
    
    NSMutableArray *capturedEventsArray;
    char *capturedEventsArrayEntryIsSelected;
    
    CFMachPortRef portRef;
    CFRunLoopSourceRef runLoopSourceRef;
    CGEventMask tappedEventsMask;
 
    EventPlaybackThreadData eventPlaybackThreadData;
    
    struct {
        NSInteger column;
        NSInteger row;
    } editedEvent;
    
    CGFloat minimumWindowHeight;
    CGFloat windowMarginHeight;
}

@property (assign) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)dealloc
{
    [self disableEventCapture];
    
    [authorizeButton release];
    [openMenuItem release];
    [saveMenuItem release];
    [findMenuItem release];
    
    [eventCaptureButton release];
    [eventsFilterBox release];
    [eventsFilterModeToggleButton release];
    [eventsFilterTokenField release];
    
    [capturedEventsPanel release];
    [capturedEventsPanelCloseButton release];
    [capturedEventsPlaybackButton release];
    
    [numberOfCapturedEventsLabel release];
    [capturedEventsBasicInfoScrollView release];
    [capturedEventsBasicInfoTableView release];
    [capturedEventsMoreInfoScrollView release];
    [capturedEventsMoreInfoTableView release];
    
    [eventByteNumberTextField release];
    [eventByteNumberStepper release];
    [eventSizeLabel release];
    [eventBytesTextView release];
    [eventNumberButton release];
    [eventBytesSearchField release];
    
    [eventFieldsDictionary release];
    [knownEventsDictionary release];
    
    [capturedEventsArray release];
    
    if(capturedEventsArrayEntryIsSelected != NULL)
        free(capturedEventsArrayEntryIsSelected);

    self.window = nil;
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSRect frame = capturedEventsPanel.frame;
    frame.size.width = self.window.frame.size.width;
    [capturedEventsPanel setFrame:frame display:NO];
    
    capturedEventsArray = [[NSMutableArray alloc] initWithCapacity:4096];
    
    eventPlaybackThreadData.appDelegate = self;
    
    eventBytesTextView.font = [NSFont fontWithName:@"Courier New" size:15];
    eventBytesTextView.textColor = [NSColor darkGrayColor];
    
    minimumWindowHeight = self.window.frame.size.height;
    windowMarginHeight = minimumWindowHeight - eventsFilterTokenField.bounds.size.height;
    
    openMenuItem.action = @selector(openFile:);
    saveMenuItem.action = nil;
    findMenuItem.action = nil;
    
    [capturedEventsMoreInfoScrollView.contentView setPostsBoundsChangedNotifications:YES];
    [capturedEventsBasicInfoScrollView.contentView setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(eventsTableViewBoundsDidChange:) name:NSViewBoundsDidChangeNotification object:capturedEventsMoreInfoScrollView.contentView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(eventsTableViewBoundsDidChange:) name:NSViewBoundsDidChangeNotification object:capturedEventsBasicInfoScrollView.contentView];
    
    eventFieldsDictionary = [[NSDictionary alloc] initWithObjectsAndKeys:
                             
                             [NSNull null], @"ev:aa:time",
                             [NSNull null], @"ev:ab:flags",
                             [NSNull null], @"ev:ac:x",
                             [NSNull null], @"ev:ad:y",
                             
                             [NSNumber numberWithUnsignedInt:kCGMouseEventNumber], @"ev:ba:m::number",
                             [NSNumber numberWithUnsignedInt:kCGMouseEventClickState], @"ev:bb:m::state",
                             [NSNumber numberWithUnsignedInt:kCGMouseEventPressure], @"ev:bc:m::pressure.",
                             [NSNumber numberWithUnsignedInt:kCGMouseEventButtonNumber], @"ev:bd:m::button",
                             [NSNumber numberWithUnsignedInt:kCGMouseEventDeltaX], @"ev:be:m::deltaX",
                             [NSNumber numberWithUnsignedInt:kCGMouseEventDeltaY], @"ev:bf:m::deltaY",
                             [NSNumber numberWithUnsignedInt:kCGMouseEventInstantMouser], @"ev:bg:m::instantMouser",
                             [NSNumber numberWithUnsignedInt:kCGMouseEventSubtype], @"ev:bh:m::subtype",
                             
                             [NSNumber numberWithUnsignedInt:kCGKeyboardEventAutorepeat], @"ev:ca:k::autorepeat",
                             [NSNumber numberWithUnsignedInt:kCGKeyboardEventKeycode], @"ev:cb:k::keycode",
                             [NSNumber numberWithUnsignedInt:kCGKeyboardEventKeyboardType], @"ev:cc:k::type",
                             
                             [NSNumber numberWithUnsignedInt:kCGScrollWheelEventDeltaAxis1], @"ev:da:s::deltaAxis1",
                             [NSNumber numberWithUnsignedInt:kCGScrollWheelEventDeltaAxis2], @"ev:db:s::deltaAxis2",
                             [NSNumber numberWithUnsignedInt:kCGScrollWheelEventDeltaAxis3], @"ev:dc:s::deltaAxis3",
                             [NSNumber numberWithUnsignedInt:kCGScrollWheelEventFixedPtDeltaAxis1], @"ev:dd:s::fixedPtDeltaAxis1.",
                             [NSNumber numberWithUnsignedInt:kCGScrollWheelEventFixedPtDeltaAxis2], @"ev:de:s::fixedPtDeltaAxis2.",
                             [NSNumber numberWithUnsignedInt:kCGScrollWheelEventFixedPtDeltaAxis3], @"ev:df:s::fixedPtDeltaAxis3.",
                             [NSNumber numberWithUnsignedInt:kCGScrollWheelEventPointDeltaAxis1], @"ev:dg:s::pointDeltaAxis1",
                             [NSNumber numberWithUnsignedInt:kCGScrollWheelEventPointDeltaAxis2], @"ev:dh:s::pointDeltaAxis2",
                             [NSNumber numberWithUnsignedInt:kCGScrollWheelEventPointDeltaAxis3], @"ev:di:s::pointDeltaAxis3",
                             [NSNumber numberWithUnsignedInt:kCGScrollWheelEventInstantMouser], @"ev:dj:s::instantMouser",
                             [NSNumber numberWithUnsignedInt:kCGScrollWheelEventIsContinuous], @"ev:dk:s::isContinuous",
                             
                             [NSNumber numberWithUnsignedInt:kCGTabletEventPointX], @"ev:ea:t::pointX",
                             [NSNumber numberWithUnsignedInt:kCGTabletEventPointY], @"ev:eb:t::pointY",
                             [NSNumber numberWithUnsignedInt:kCGTabletEventPointZ], @"ev:ec:t::pointZ",
                             [NSNumber numberWithUnsignedInt:kCGTabletEventPointButtons], @"ev:ed:t::pointButtons",
                             [NSNumber numberWithUnsignedInt:kCGTabletEventPointPressure], @"ev:ee:t::pointPressure.",
                             [NSNumber numberWithUnsignedInt:kCGTabletEventTiltX], @"ev:ef:t::tiltX.",
                             [NSNumber numberWithUnsignedInt:kCGTabletEventTiltY], @"ev:eg:t::tiltY.",
                             [NSNumber numberWithUnsignedInt:kCGTabletEventRotation], @"ev:eh:t::rotation.",
                             [NSNumber numberWithUnsignedInt:kCGTabletEventTangentialPressure], @"ev:ei:t::tangentialPressure.",
                             [NSNumber numberWithUnsignedInt:kCGTabletEventDeviceID], @"ev:ej:t::deviceID",
                             [NSNumber numberWithUnsignedInt:kCGTabletEventVendor1], @"ev:ek:t::vendor1",
                             [NSNumber numberWithUnsignedInt:kCGTabletEventVendor2], @"ev:el:t::vendor2",
                             [NSNumber numberWithUnsignedInt:kCGTabletEventVendor3], @"ev:em:t::vendor3",
                             
                             [NSNumber numberWithUnsignedInt:kCGTabletProximityEventVendorID], @"ev:fa:p::vendorID",
                             [NSNumber numberWithUnsignedInt:kCGTabletProximityEventTabletID], @"ev:fb:p::tabletID",
                             [NSNumber numberWithUnsignedInt:kCGTabletProximityEventPointerID], @"ev:fc:p::pointerID",
                             [NSNumber numberWithUnsignedInt:kCGTabletProximityEventDeviceID], @"ev:fd:p::deviceID",
                             [NSNumber numberWithUnsignedInt:kCGTabletProximityEventSystemTabletID], @"ev:fe:p::systemTabletID",
                             [NSNumber numberWithUnsignedInt:kCGTabletProximityEventVendorPointerType], @"ev:ff:p::vendorPointerType",
                             [NSNumber numberWithUnsignedInt:kCGTabletProximityEventVendorPointerSerialNumber], @"ev:fg:p::vendorPointerSerialNumber",
                             [NSNumber numberWithUnsignedInt:kCGTabletProximityEventVendorUniqueID], @"ev:fh:p::vendorUniqueID",
                             [NSNumber numberWithUnsignedInt:kCGTabletProximityEventCapabilityMask], @"ev:fi:p::capabilityMask",
                             [NSNumber numberWithUnsignedInt:kCGTabletProximityEventPointerType], @"ev:fj:p::pointerType",
                             [NSNumber numberWithUnsignedInt:kCGTabletProximityEventEnterProximity], @"ev:fk:p::enterProximity",
                             
                             nil];
    
    NSTableColumn *tableColumn = capturedEventsMoreInfoTableView.tableColumns.lastObject;
    NSCell *headerCell = tableColumn.headerCell;
    NSCell *dataCell = tableColumn.dataCell;
    [capturedEventsMoreInfoTableView removeTableColumn:tableColumn];
    
    for(NSString *title in [eventFieldsDictionary.allKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)])
    {
        tableColumn = [[[NSTableColumn alloc] initWithIdentifier:title] autorelease];
        tableColumn.headerCell = [[headerCell copy] autorelease];
        title = [[title substringFromIndex:6] stringByReplacingOccurrencesOfString:@"." withString:@""];
        [tableColumn.headerCell setTitle:title];
        tableColumn.headerToolTip = title;
        tableColumn.dataCell = [[dataCell copy] autorelease];
        [capturedEventsMoreInfoTableView addTableColumn:tableColumn];
    }
    
    knownEventsDictionary = [[NSDictionary alloc] initWithObjectsAndKeys:
                             @"NSLeftMouseDown", [NSNumber numberWithUnsignedInteger:NSLeftMouseDown],
                             @"NSLeftMouseUp", [NSNumber numberWithUnsignedInteger:NSLeftMouseUp],
                             @"NSRightMouseDown", [NSNumber numberWithUnsignedInteger:NSRightMouseDown],
                             @"NSRightMouseUp", [NSNumber numberWithUnsignedInteger:NSRightMouseUp],
                             @"NSMouseMoved", [NSNumber numberWithUnsignedInteger:NSMouseMoved],
                             @"NSLeftMouseDragged", [NSNumber numberWithUnsignedInteger:NSLeftMouseDragged],
                             @"NSRightMouseDragged", [NSNumber numberWithUnsignedInteger:NSRightMouseDragged],
                             @"NSMouseEntered", [NSNumber numberWithUnsignedInteger:NSMouseEntered],
                             @"NSMouseExited", [NSNumber numberWithUnsignedInteger:NSMouseExited],
                             @"NSKeyDown", [NSNumber numberWithUnsignedInteger:NSKeyDown],
                             @"NSKeyUp", [NSNumber numberWithUnsignedInteger:NSKeyUp],
                             @"NSFlagsChanged", [NSNumber numberWithUnsignedInteger:NSFlagsChanged],
                             @"NSSystemDefined", [NSNumber numberWithUnsignedInteger:NSSystemDefined],
                             @"NSApplicationDefined", [NSNumber numberWithUnsignedInteger:NSApplicationDefined],
                             @"NSPeriodic", [NSNumber numberWithUnsignedInteger:NSPeriodic],
                             @"NSCursorUpdate", [NSNumber numberWithUnsignedInteger:NSCursorUpdate],
                             @"NSScrollWheel", [NSNumber numberWithUnsignedInteger:NSScrollWheel],
                             @"NSTabletPoint", [NSNumber numberWithUnsignedInteger:NSTabletPoint],
                             @"NSTabletProximity", [NSNumber numberWithUnsignedInteger:NSTabletProximity],
                             @"NSOtherMouseDown", [NSNumber numberWithUnsignedInteger:NSOtherMouseDown],
                             @"NSOtherMouseUp", [NSNumber numberWithUnsignedInteger:NSOtherMouseUp],
                             @"NSOtherMouseDragged", [NSNumber numberWithUnsignedInteger:NSOtherMouseDragged],
                             @"NSEventTypeGesture", [NSNumber numberWithUnsignedInteger:NSEventTypeGesture],
                             @"NSEventTypeMagnify", [NSNumber numberWithUnsignedInteger:NSEventTypeMagnify],
                             @"NSEventTypeSwipe", [NSNumber numberWithUnsignedInteger:NSEventTypeSwipe],
                             @"NSEventTypeRotate", [NSNumber numberWithUnsignedInteger:NSEventTypeRotate],
                             @"NSEventTypeBeginGesture", [NSNumber numberWithUnsignedInteger:NSEventTypeBeginGesture],
                             @"NSEventTypeEndGesture", [NSNumber numberWithUnsignedInteger:NSEventTypeEndGesture],
                             @"NSEventTypeSmartMagnify", [NSNumber numberWithUnsignedInteger:NSEventTypeSmartMagnify],
                             @"NSEventTypeQuickLook", [NSNumber numberWithUnsignedInteger:NSEventTypeQuickLook],
                             nil ];
    
    NSMutableCharacterSet *tokenizingCharacterSet = [[[NSTokenField defaultTokenizingCharacterSet] copy] autorelease];
    [tokenizingCharacterSet addCharactersInString:@" "];
    eventsFilterTokenField.tokenizingCharacterSet = tokenizingCharacterSet;

    //capturedEventsPanel.preventsApplicationTerminationWhenModal = NO;
    
    if([self authorizeOrCheckAuthorization:NO])
    {
        authorizeButton.hidden = YES;
        NSRect frame = eventsFilterBox.frame;
        frame.size.width = eventsFilterBox.superview.frame.size.width + - frame.origin.x + 5;
        eventsFilterBox.frame = frame;
    }
    
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
}

- (void)windowDidResize:(NSNotification *)notification
{
    if(self.window.inLiveResize)
        [self resizeEventsFilterTokenField];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

// Authorization ***************************************************************
// Restart the application with elevated privileges to capture key events, etc.

- (BOOL)authorizeOrCheckAuthorization:(BOOL)authorize
{
    BOOL authorized = NO;
    AuthorizationRef authorizationRef;
    
    if(AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authorizationRef) == errAuthorizationSuccess)
    {
        NSString *path = [[NSBundle mainBundle] executablePath];
        AuthorizationItem item;
        item.name = kAuthorizationRightExecute;
        item.flags = 0;
        item.value = NULL;
        item.valueLength = 0;
        AuthorizationRights rights;
        rights.count = 1;
        rights.items = &item;
        
        if(AuthorizationCopyRights(authorizationRef, &rights, NULL, (authorize ? kAuthorizationFlagInteractionAllowed : 0) | kAuthorizationFlagDefaults | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights, NULL) == errAuthorizationSuccess)
            authorized = authorize ? (AuthorizationExecuteWithPrivileges(authorizationRef, path.UTF8String, kAuthorizationFlagDefaults, NULL, NULL) == errAuthorizationSuccess) : YES;
        
        AuthorizationFree(authorizationRef, kAuthorizationFlagDefaults);
    }
    
    return authorized;
}

- (IBAction)authorize:(id)sender
{
    if([self authorizeOrCheckAuthorization:YES])
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
}

// Capture Events **************************************************************

static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef eventRef, AppDelegate *appDelegate)
{
    static CGEventTimestamp previousTimestamp;
    CGEventTimestamp timestamp = CGEventGetTimestamp(eventRef);
    CGEventRef eventRefCopy = CGEventCreateCopy(eventRef);
    
    if(appDelegate->capturedEventsArray.count < 1)
        previousTimestamp = timestamp;
    
    if(previousTimestamp > timestamp)
    {
        CGEventSetTimestamp(eventRefCopy, previousTimestamp - timestamp);
        timestamp = previousTimestamp;
    }
    else
        CGEventSetTimestamp(eventRefCopy, timestamp - previousTimestamp);
    
    NSEvent *event = [NSEvent eventWithCGEvent:eventRefCopy];
    
    if(event != nil && (appDelegate->tappedEventsMask & NSEventMaskFromType(event.type)))
    {
        [appDelegate->capturedEventsArray addObject:event];
        previousTimestamp = timestamp;
    }
    
    CFRelease(eventRefCopy);
    return eventRef;
}

- (void)disableEventCapture
{
    if(runLoopSourceRef != nil && CFRunLoopContainsSource(CFRunLoopGetMain(), runLoopSourceRef, kCFRunLoopCommonModes))
    {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSourceRef, kCFRunLoopCommonModes);
        
        if(portRef != nil)
        {
            CFMachPortInvalidate(portRef);
            CFRelease(portRef);
            portRef = nil;
        }
        
        if(runLoopSourceRef != nil)
        {
            CFRelease(runLoopSourceRef);
            runLoopSourceRef = nil;
        }
    }
}

- (void)clearCapturedEvents
{
    [capturedEventsArray removeAllObjects];
    [capturedEventsMoreInfoTableView reloadData];
    [capturedEventsBasicInfoTableView reloadData];
    
    if(capturedEventsArrayEntryIsSelected != NULL)
    {
        free(capturedEventsArrayEntryIsSelected);
        capturedEventsArrayEntryIsSelected = NULL;
    }
}

- (void)readyEventCapture
{
    openMenuItem.action = nil;
    eventsFilterModeToggleButton.enabled = NO;
    eventsFilterTokenField.enabled = NO;
    authorizeButton.enabled = NO;
    [self clearCapturedEvents];
}

- (void)showCapturedEvents
{
    if(capturedEventsArray.count > 0 && (capturedEventsArrayEntryIsSelected = (char *)malloc(capturedEventsArray.count * sizeof(char))) != NULL)
    {
        memset(capturedEventsArrayEntryIsSelected, 1, capturedEventsArray.count * sizeof(char));
        [capturedEventsBasicInfoTableView reloadData];
        [capturedEventsMoreInfoTableView reloadData];
        eventNumberButton.tag = -1;
        [self capturedEventsTableView:capturedEventsMoreInfoTableView showMoreInfoForRow:0];
        numberOfCapturedEventsLabel.title = [NSString stringWithFormat:@" %lu event%s captured", (unsigned long)capturedEventsArray.count, (capturedEventsArray.count > 1) ? "s" : ""];
        
        NSInteger columnIndex;
        CGFloat columnWidth;
        CGFloat cellWidth;
        NSInteger row[5] = { capturedEventsArray.count - 1, capturedEventsArray.count * 3 / 4, capturedEventsArray.count / 2, capturedEventsArray.count / 4, 0 };
        int i;
        
        for(NSTableColumn *column in capturedEventsMoreInfoTableView.tableColumns)
        {
            columnIndex = [capturedEventsMoreInfoTableView columnWithIdentifier:column.identifier];
            columnWidth = 0;
            
            for(i = 0; i < 5; i++)
            {
                if((cellWidth = [capturedEventsMoreInfoTableView preparedCellAtColumn:columnIndex row:row[i]].cellSize.width) > columnWidth)
                    columnWidth = cellWidth;
            }
            
            column.width = columnWidth;
        }
        
        [capturedEventsMoreInfoTableView scrollColumnToVisible:0];
        [capturedEventsMoreInfoTableView scrollRowToVisible:0];
        [[NSApplication sharedApplication] beginSheet:capturedEventsPanel modalForWindow:self.window modalDelegate:self didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) contextInfo:nil];
        saveMenuItem.action = @selector(saveToFile:);
        findMenuItem.action = @selector(searchEventBytes:);
    }
    else
    {
        [self clearCapturedEvents];
        openMenuItem.action = @selector(openFile:);
    }
    
    eventsFilterModeToggleButton.enabled = YES;
    eventsFilterTokenField.enabled = YES;
    authorizeButton.enabled = YES;
}

- (IBAction)toggleEventCapture:(NSButton *)sender
{
    if(sender.state == NSOnState)
    {
        [self readyEventCapture];
        
        CGEventMask eventMask = 0;
        int bit;
        [self eventsFilterTokenFieldDidEndEditing];
        
        for(NSString *event in eventsFilterTokenField.objectValue)
        {
            if((bit = ([knownEventsDictionary.allValues containsObject:event]) ? [[knownEventsDictionary allKeysForObject:event].lastObject intValue] : [event intValue]) > 0)
                eventMask |= CGEventMaskBit(bit);
        }
        
        if(eventMask == 0)
            eventMask = kCGEventMaskForAllEvents;
        
        if(eventsFilterModeToggleButton.state == NSOnState)
            eventMask = ~eventMask;
        
        if(eventMask == 0)
        {
            sender.state = NSOffState;
            [self toggleEventCapture:sender];
        }
        else
        {
            [self disableEventCapture];
            tappedEventsMask = eventMask;
            
            if((eventMask & (NSEventMaskMagnify | NSEventMaskSwipe | NSEventMaskRotate | NSEventMaskBeginGesture | NSEventMaskEndGesture | NSEventMaskSmartMagnify)))
                eventMask |= NSEventMaskGesture;
            
            portRef = CGEventTapCreate(kCGHIDEventTap, 0, kCGEventTapOptionListenOnly, eventMask, (CGEventTapCallBack)eventTapCallback, self);
            runLoopSourceRef = CFMachPortCreateRunLoopSource(NULL, portRef, 0);
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSourceRef, kCFRunLoopCommonModes);
        }
    }
    else
    {
        [self disableEventCapture];
        
        if((tappedEventsMask & CGEventMaskBit(kCGEventLeftMouseDown)))
        {
            NSEventType eventType;
            
            while(capturedEventsArray.count > 0)
            {
                eventType = [(NSEvent *)[capturedEventsArray lastObject] type];
                [capturedEventsArray removeLastObject];
                
                if(eventType == NSLeftMouseDown)
                    break;
            }
        }
        
        [self showCapturedEvents];
    }
}

// Events Filter

- (NSArray *)tokenField:(NSTokenField *)tokenField completionsForSubstring:(NSString *)substring indexOfToken:(NSInteger)tokenIndex indexOfSelectedItem:(NSInteger *)selectedIndex
{
    NSMutableArray *completions = [NSMutableArray arrayWithCapacity:50];
    NSArray *tokens = tokenField.objectValue;
    
    for(NSString *string in knownEventsDictionary.allValues)
    {
        if([string compare:substring options:NSCaseInsensitiveSearch range:NSMakeRange(0, substring.length)] == NSOrderedSame && ![tokens containsObject:string])
            [completions addObject:string];
    }
    
    return [completions sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
}

- (NSArray *)tokenField:(NSTokenField *)tokenField shouldAddObjects:(NSArray *)tokens atIndex:(NSUInteger)index
{
    NSMutableArray *newTokenList = [NSMutableArray arrayWithCapacity:tokens.count];
    NSString *newToken;
    NSUInteger tokenIndex;
    --index;
    
    for(NSString *token in tokens)
    {
        ++index;
        
        if(![knownEventsDictionary.allValues containsObject:token])
        {
            NSNumberFormatter *numberFormatter = [[NSNumberFormatter new] autorelease];
            numberFormatter.allowsFloats = NO;
            NSNumber *number = [numberFormatter numberFromString:token];
            
            if(number == nil || number.intValue < 1 || number.intValue > 63)
                continue;
            
            newToken = [knownEventsDictionary objectForKey:[NSNumber numberWithUnsignedInteger:number.intValue]];
            
            if(newToken != nil)
                token = newToken;
        }
        
        tokenIndex = [(NSArray *)tokenField.objectValue indexOfObject:token];
        
        if(tokenIndex == NSNotFound || tokenIndex == index)
            [newTokenList addObject:token];
    }
    
    return newTokenList;
}

- (void)resizeEventsFilterTokenField
{
    NSRect rect = eventsFilterTokenField.bounds;
    rect.size.height = 999999999;
    CGFloat height = [eventsFilterTokenField.cell cellSizeForBounds:rect].height;
    rect = self.window.frame;
    rect.size.height = windowMarginHeight + height;
    
    if(rect.size.height < minimumWindowHeight)
        rect.size.height = minimumWindowHeight;
    
    if(self.window.frame.size.height != rect.size.height)
    {
        rect.origin.y += (self.window.frame.size.height - rect.size.height);
        [self.window setFrame:rect display:YES animate:YES];
        NSSize size = self.window.contentMinSize;
        size.height = [self.window.contentView bounds].size.height;
        self.window.contentMinSize = size;
        size.width = self.window.contentMaxSize.width;
        self.window.contentMaxSize = size;
    }
}

- (void)eventsFilterTokenFieldTextDidChange
{
    (void)eventsFilterTokenField.stringValue;
    [self resizeEventsFilterTokenField];
}

- (void)eventsFilterTokenFieldDidEndEditing
{
    NSArray *tokens = [self tokenField:eventsFilterTokenField shouldAddObjects:eventsFilterTokenField.objectValue atIndex:0];
    NSMutableString *stringValue = [NSMutableString string];
    
    for(NSString *string in tokens)
        [stringValue appendString:[NSString stringWithFormat:@"%@ ", string]];
    
    eventsFilterTokenField.stringValue = stringValue;
}

// Captured Events *************************************************************

// Replay Events

static void cleanupEventPlaybackThread(EventPlaybackThreadData *data)
{
    data->isRunning = NO;
    data->appDelegate->capturedEventsPlaybackButton.state = NSOffState;
    
    if(data->autoreleasePool != nil)
    {
        [data->autoreleasePool release];
        data->autoreleasePool = nil;
    }
}

static void * eventPlaybackThread(EventPlaybackThreadData *data)
{
    pthread_cleanup_push((void (*)(void *))cleanupEventPlaybackThread, data);
    
    NSArray *events = data->appDelegate->capturedEventsArray;
    char *isSelected = data->appDelegate->capturedEventsArrayEntryIsSelected;
    data->autoreleasePool = [NSAutoreleasePool new];
    struct timespec delay;
    int i = 0;
    
    for(NSEvent *event in events)
    {
        if(isSelected[i++])
        {
            delay.tv_sec = (long)event.timestamp;
            delay.tv_nsec = (long)((event.timestamp - delay.tv_sec) * 1000000000);
            nanosleep(&delay, NULL);
            CGEventPost(kCGHIDEventTap, event.CGEvent);
        }
    }
    
    pthread_cleanup_pop(1);
    return NULL;
}

- (IBAction)playCapturedEvents:(NSButton *)sender
{
    if(sender.state == NSOnState)
    {
        if(!eventPlaybackThreadData.isRunning)
        {
            if(!(eventPlaybackThreadData.isRunning = (pthread_create(&eventPlaybackThreadData.ID, NULL, (void *(*)(void *))eventPlaybackThread, &eventPlaybackThreadData) == 0)))
                sender.state = NSOffState;
        }
    }
    else if(eventPlaybackThreadData.isRunning)
    {
        pthread_cancel(eventPlaybackThreadData.ID);
        pthread_join(eventPlaybackThreadData.ID, NULL);
    }
}

// Captured Events Panel

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    findMenuItem.action = nil;
    saveMenuItem.action = nil;
    openMenuItem.action = @selector(openFile:);
}

- (IBAction)closeCapturedEventsPanel:(NSButton *)sender
{
    capturedEventsPlaybackButton.state = NSOffState;
    [self playCapturedEvents:capturedEventsPlaybackButton];
    [capturedEventsMoreInfoTableView abortEditing];
    [[NSApplication sharedApplication] endSheet:capturedEventsPanel];
    [capturedEventsPanel orderOut:self];
}

// Captured Events Info Table

- (void)eventsTableViewBoundsDidChange:(NSNotification *)notification
{
    NSClipView *contentView = notification.object;
    CGFloat y = contentView.documentVisibleRect.origin.y;
    NSScrollView *scrollView = (contentView == capturedEventsBasicInfoScrollView.contentView) ? capturedEventsMoreInfoScrollView : capturedEventsBasicInfoScrollView;
    contentView = scrollView.contentView;
    [contentView scrollToPoint:NSMakePoint(contentView.documentVisibleRect.origin.x, y)];
    [scrollView reflectScrolledClipView:scrollView.contentView];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return capturedEventsArray.count;
}

- (NSString *)stringFromEventType:(NSEventType)eventType
{
    NSString *string = [knownEventsDictionary objectForKey:[NSNumber numberWithUnsignedInteger:eventType]];
    return ((string == nil) ? @"" : [string substringFromIndex:2]);
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSEvent *event = [capturedEventsArray objectAtIndex:row];
    
    if(tableView == capturedEventsBasicInfoTableView)
    {
        if([tableColumn.identifier isEqualToString:@"select"])
        {
            [(NSButtonCell *)tableColumn.dataCell setState:(capturedEventsArrayEntryIsSelected[row] ? NSOnState : NSOffState)];
            return tableColumn.dataCell;
        }
        else if([tableColumn.identifier isEqualToString:@"number"])
        {
            capturedEventsBasicInfoScrollView.verticalScroller.hidden = YES; // TODO: find a better place for this
            return [NSString stringWithFormat:@"%ld", row + 1];
        }
        else if([tableColumn.identifier isEqualToString:@"type"])
            return [NSString stringWithFormat:@"%3lu · %@", (unsigned long)event.type, [self stringFromEventType:event.type]];
    }
    else
    {
        NSString *identifier = [tableColumn.headerCell stringValue];
        
        if([identifier isEqualToString:@"time"])
            return [NSString stringWithFormat:@"%f", event.timestamp];
        else if([identifier isEqualToString:@"flags"])
            return [NSString stringWithFormat:@"0x%.8llx", CGEventGetFlags(event.CGEvent)];
        else if([identifier isEqualToString:@"x"])
            return [NSString stringWithFormat:@"%f", CGEventGetLocation(event.CGEvent).x];
        else if([identifier isEqualToString:@"y"])
            return [NSString stringWithFormat:@"%f", CGEventGetLocation(event.CGEvent).y];
        
        NSNumber *eventField = [eventFieldsDictionary objectForKey:tableColumn.identifier];
        
        if(eventField != nil)
        {
            if([tableColumn.identifier hasSuffix:@"."])
                return [NSString stringWithFormat:@"%f", CGEventGetDoubleValueField(event.CGEvent, eventField.unsignedIntValue)];
            
            return [NSString stringWithFormat:@"%lld", CGEventGetIntegerValueField(event.CGEvent, eventField.unsignedIntValue)];
        }
    }
    
    return nil;
}

- (NSRange)locateEventFieldBytes:(NSEvent *)event tableColumn:(NSTableColumn *)tableColumn
{
    CGEventRef eventRef = CGEventCreateCopy(event.CGEvent);
    NSRange range = NSMakeRange(NSNotFound, 0);
    
    if(eventRef != NULL)
    {
        NSData *data[2] = { NULL, NULL };
        
        if([tableColumn.identifier hasPrefix:@"ev:a"])
        {
            NSString *identifier = [tableColumn.headerCell stringValue];
            
            if([identifier isEqualToString:@"time"])
            {
                CGEventTimestamp timestamp = 0ULL;
                CGEventSetTimestamp(eventRef, timestamp);
                data[0] = (NSData *)CGEventCreateData(NULL, eventRef);
                timestamp = ~(0ULL);
                CGEventSetTimestamp(eventRef, timestamp);
                data[1] = (NSData *)CGEventCreateData(NULL, eventRef);
            }
            else if([identifier isEqualToString:@"flags"])
            {
                CGEventFlags flags = 0ULL;
                CGEventSetFlags(eventRef, flags);
                data[0] = (NSData *)CGEventCreateData(NULL, eventRef);
                flags = ~(0ULL);
                CGEventSetFlags(eventRef, flags);
                data[1] = (NSData *)CGEventCreateData(NULL, eventRef);
            }
            else
            {
                CGPoint location = { 0, 0 };
                CGEventSetLocation(eventRef, location);
                data[0] = (NSData *)CGEventCreateData(NULL, eventRef);
                
                if([identifier isEqualToString:@"x"])
                    location.x = (CGFloat)1 / 3;
                else
                    location.y = (CGFloat)1 / 3;
                
                CGEventSetLocation(eventRef, location);
                data[1] = (NSData *)CGEventCreateData(NULL, eventRef);
            }
        }
        else
        {
            CGEventField field = [[eventFieldsDictionary objectForKey:tableColumn.identifier] unsignedIntValue];
            
            if([tableColumn.identifier hasSuffix:@"."])
            {
                double value = 0;
                CGEventSetDoubleValueField(eventRef, field, value);
                data[0] = (NSData *)CGEventCreateData(NULL, eventRef);
                value = (double)1 / 3;
                CGEventSetDoubleValueField(eventRef, field, value);
                data[1] = (NSData *)CGEventCreateData(NULL, eventRef);
            }
            else
            {
                int64_t value = 0ULL;
                CGEventSetIntegerValueField(eventRef, field, value);
                data[0] = (NSData *)CGEventCreateData(NULL, eventRef);
                value = ~(0ULL);
                CGEventSetIntegerValueField(eventRef, field, value);
                data[1] = (NSData *)CGEventCreateData(NULL, eventRef);
            }
        }
        
        if(data[0].length != 0 && data[1].length != 0)
        {
            NSRange range = NSMakeRange(0, 0);
            
            for(int i = 0; i <= data[0].length; i++)
            {
                if(i < data[0].length && ((char *)data[0].bytes)[i] != ((char *)data[1].bytes)[i])
                {
                    if(range.length == 0)
                        range.location = i;
                    
                    ++range.length;
                }
                else if(range.length != 0)
                {
                    range.location *= 3;
                    range.length = (range.length * 3) - 1;
                    [self selectEventBytesAtRange:range flash:YES];
                    range.length = 0;
                }
            }
        }
        
        if(data[0] != NULL)
            CFRelease(data[0]);
        
        if(data[1] != NULL)
            CFRelease(data[1]);
        
        CFRelease(eventRef);
    }

    return range;
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    editedEvent.column = [tableView columnWithIdentifier:tableColumn.identifier];
    editedEvent.row = row;
    [self showEditedEvent];
    [self capturedEventsTableView:tableView showMoreInfoForRow:row];
    [self locateEventFieldBytes:[capturedEventsArray objectAtIndex:row] tableColumn:tableColumn];
    return YES;
}

- (void)refreshEventBytesTextView:(NSData *)data
{
    eventBytesTextView.delegate = nil;
    NSMutableString *string = [NSMutableString stringWithCapacity:(data.length * 3)];
    
    for(int i = 0; i < data.length; i++)
        [string appendFormat:@"%.2x ", ((unsigned char *)data.bytes)[i]];
    
    eventBytesTextView.string = [string substringToIndex:(string.length - 1)];
    eventBytesTextView.delegate = self;
}

- (void)capturedEventsTableView:(NSTableView *)tableView showMoreInfoForRow:(NSInteger)row
{
    if(eventNumberButton.tag != row)
    {
        NSData *data = (NSData *)CGEventCreateData(NULL, [[capturedEventsArray objectAtIndex:row] CGEvent]);
        eventNumberButton.tag = row;
        eventNumberButton.title = [NSString stringWithFormat:@"%05ld", row + 1];
        eventSizeLabel.stringValue = [NSString stringWithFormat:@"%lu bytes", (unsigned long)data.length];
        [self refreshEventBytesTextView:data];
        [self selectEventBytesAtRange:NSMakeRange(0, 2) flash:NO];
        eventByteNumberTextField.intValue = 0;
        eventByteNumberStepper.intValue = 0;
        eventByteNumberStepper.maxValue = (double)data.length - 1;
        CFRelease(data);
    }
}

- (NSIndexSet *)tableView:(NSTableView *)tableView selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes
{
    if(proposedSelectionIndexes.count < 1)
        proposedSelectionIndexes = tableView.selectedRowIndexes;
    
    [tableView selectRowIndexes:proposedSelectionIndexes byExtendingSelection:NO];
    tableView = (tableView == capturedEventsBasicInfoTableView) ? capturedEventsMoreInfoTableView : capturedEventsBasicInfoTableView;
    [tableView selectRowIndexes:proposedSelectionIndexes byExtendingSelection:NO];
    return proposedSelectionIndexes;
}

- (void)capturedEventsTableView:(NSTableView *)tableView toggleSelectionForRows:(NSIndexSet *)rows
{
    char isSelected = !capturedEventsArrayEntryIsSelected[rows.firstIndex];
    
    [rows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        capturedEventsArrayEntryIsSelected[idx] = isSelected;
    }];
    
    [capturedEventsBasicInfoTableView reloadData];
}

- (IBAction)showEvent:(NSButton *)sender
{
    [capturedEventsBasicInfoTableView scrollRowToVisible:sender.tag];
    [self tableView:capturedEventsBasicInfoTableView selectionIndexesForProposedSelection:[NSIndexSet indexSetWithIndex:sender.tag]];
}

- (void)showEditedEvent
{
    [capturedEventsMoreInfoTableView scrollColumnToVisible:editedEvent.column];
    [capturedEventsMoreInfoTableView scrollRowToVisible:editedEvent.row];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if(tableView == capturedEventsBasicInfoTableView)
    {
        if([tableColumn.identifier isEqualToString:@"select"])
        {
            capturedEventsArrayEntryIsSelected[row] = [object boolValue];
            [(NSButtonCell *)tableColumn.dataCell setState:(capturedEventsArrayEntryIsSelected[row] ? NSOnState : NSOffState)];
        }
    }
    else
    {
        BOOL replace = NO;
        CGEventRef eventRef = CGEventCreateCopy([[capturedEventsArray objectAtIndex:row] CGEvent]);

        if([[tableColumn.headerCell stringValue] isEqualToString:@"flags"])
        {
            if([object hasPrefix:@"x"] || [object hasPrefix:@"X"])
                object = [object substringFromIndex:1];
            
            NSScanner *scanner = [NSScanner scannerWithString:object];
            unsigned long long value;
            
            if([scanner scanHexLongLong:&value] && scanner.isAtEnd)
            {
                CGEventSetFlags(eventRef, value);
                replace = (value == CGEventGetFlags(eventRef));
            }
        }
        else
        {
            NSNumberFormatter *numberFormatter = [[NSNumberFormatter new] autorelease];
            NSNumber *number = [numberFormatter numberFromString:object];
            
            if(number != nil)
            {
                if([tableColumn.identifier hasPrefix:@"ev:a"])
                {
                    NSString *identifier = [tableColumn.headerCell stringValue];
                    
                    if([identifier isEqualToString:@"time"])
                    {
                        CGEventTimestamp timestamp = (CGEventTimestamp)(number.doubleValue * 1000000000);
                        CGEventSetTimestamp(eventRef, timestamp);
                        replace = (CGEventGetTimestamp(eventRef) == timestamp);
                    }
                    else
                    {
                        CGPoint location = CGEventGetLocation(eventRef);
                        
                        if([identifier isEqualToString:@"x"])
                            location.x = number.doubleValue;
                        else
                            location.y = number.doubleValue;
                        
                        CGEventSetLocation(eventRef, location);
                        
                        if([tableColumn.identifier isEqualToString:@"x"])
                            replace = (CGEventGetLocation(eventRef).x == location.x);
                        else
                            replace = (CGEventGetLocation(eventRef).y == location.y);
                    }
                }
                else
                {
                    CGEventField field = [[eventFieldsDictionary objectForKey:tableColumn.identifier] unsignedIntValue];
                    
                    if([tableColumn.identifier hasSuffix:@"."])
                    {
                        CGEventSetDoubleValueField(eventRef, field, number.doubleValue);
                        replace = (CGEventGetDoubleValueField(eventRef, field) == number.doubleValue);
                    }
                    else
                    {
                        CGEventSetIntegerValueField(eventRef, field, number.integerValue);
                        replace = (CGEventGetIntegerValueField(eventRef, field) == number.doubleValue);
                    }
                }
            }
        }
        
        if(replace)
        {
            NSRange range = eventBytesTextView.selectedRange;
            NSData *data = (NSData *)CGEventCreateData(NULL, eventRef);
            [capturedEventsArray replaceObjectAtIndex:row withObject:[NSEvent eventWithCGEvent:eventRef]];
            [self refreshEventBytesTextView:data];
            [self selectEventBytesAtRange:range flash:YES];
            CFRelease(data);
        }
        
        CFRelease(eventRef);
    }
}

// Captured Events Split View

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex
{
    return 100;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex
{
    return ((splitView.isVertical ? splitView.frame.size.width : splitView.frame.size.height) - 100);
}

// Captured Event Bytes Text View

- (NSRange)textView:(NSTextView *)textView willChangeSelectionFromCharacterRange:(NSRange)oldSelectedCharRange toCharacterRange:(NSRange)newSelectedCharRange
{
    if(newSelectedCharRange.length < 2)
    {
        int location = (int)newSelectedCharRange.location;
        
        if(oldSelectedCharRange.length == 1 && (oldSelectedCharRange.location - newSelectedCharRange.location) == 0)
        {
            location -= 2;
        
            if(location < 0)
                location = 0;
        }
        
        if((location % 3) == 2)
        {
            ++location;
            
            if(location >= textView.string.length)
                location = (int)textView.string.length - 1;
        }
        
        newSelectedCharRange.location = (NSUInteger)location;
        newSelectedCharRange.length = 1;
    }
    
    eventByteNumberTextField.intValue = (newSelectedCharRange.location / 3);
    eventByteNumberStepper.intValue = eventByteNumberTextField.intValue;
    return newSelectedCharRange;
}

- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString
{
    return NO;
}

- (void)selectEventBytesAtRange:(NSRange)range flash:(BOOL)flash
{
    if(range.location == NSNotFound)
        range = NSMakeRange(0, 0);
    
    eventBytesTextView.selectedRange = range;
    [eventBytesTextView scrollRangeToVisible:eventBytesTextView.selectedRange];
    
    if(flash)
        [eventBytesTextView showFindIndicatorForRange:range];
}

// Captured Event Byte Number

- (void)eventByteNumberTextFieldDidEndEditing
{
    NSNumberFormatter *numberFormatter = [[NSNumberFormatter new] autorelease];
    numberFormatter.allowsFloats = NO;
    NSNumber *number = [numberFormatter numberFromString:eventByteNumberTextField.stringValue];
    
    if(number != nil && (number.intValue >= 0 && number.intValue <= (int)eventByteNumberStepper.maxValue))
        eventByteNumberStepper.intValue = number.intValue;
    
    [self setSelectedEventByte:nil];
}

- (IBAction)setSelectedEventByte:(id)sender
{
    [eventByteNumberTextField.window makeFirstResponder:nil];
    eventByteNumberTextField.intValue = eventByteNumberStepper.intValue;
    [self selectEventBytesAtRange:NSMakeRange(eventByteNumberStepper.intValue * 3, 2) flash:NO];
}

// Search Captured Event Bytes

- (IBAction)searchEventBytes:(id)sender
{
    [eventBytesSearchField becomeFirstResponder];
    NSString *searchString = eventBytesSearchField.stringValue;
    
    if(searchString.length > 0)
    {
        NSUInteger index = [[eventBytesTextView.string substringWithRange:eventBytesTextView.selectedRange] isEqualToString:searchString] ? (eventBytesTextView.selectedRange.location + 1) : 0;
        NSRange range;
        
        while(1)
        {
            range = [[eventBytesTextView.string substringFromIndex:index] rangeOfString:searchString options:NSCaseInsensitiveSearch];
        
            if(range.location == NSNotFound)
            {
                NSBeep();
                
                if(index == 0)
                    break;
                
                index = 0;
            }
            else
            {
                range.location += index;
                break;
            }
        }

        [self selectEventBytesAtRange:range flash:YES];
    }
}

// Save Captured Events To File ************************************************

- (void)saveToFile:(id)sender
{
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    [savePanel beginSheetModalForWindow:nil completionHandler:^(NSInteger result) {
        if(result == NSFileHandlingPanelOKButton)
        {
            uint32_t size;
            NSData *data;
            BOOL first = YES;
            BOOL failed;
            int i = 0;
            NSOutputStream *outputStream = [NSOutputStream outputStreamWithURL:savePanel.URL append:NO];
            [outputStream open];
            
            for(NSEvent *event in capturedEventsArray)
            {
                if(capturedEventsArrayEntryIsSelected[i++])
                {
                    if(first)
                    {
                        CGEventRef eventRef = CGEventCreateCopy(event.CGEvent);
                        
                        if(eventRef == NULL)
                            break;
                        
                        CGEventSetTimestamp(eventRef, 0);
                        data = (NSData *)CGEventCreateData(NULL, eventRef);
                        CFRelease(eventRef);
                        first = NO;
                    }
                    else
                        data = (NSData *)CGEventCreateData(NULL, event.CGEvent);
                    
                    if(data == NULL)
                        break;

                    size = (uint32_t)data.length;
                    failed = ([outputStream write:(const uint8_t *)&size maxLength:sizeof(size)] != sizeof(size) || [outputStream write:(const uint8_t *)data.bytes maxLength:size] != size);
                    CFRelease(data);
                    
                    if(failed)
                        break;
                }
            }
            
            [outputStream close];
        }
    }];
}

// Open Events File ************************************************************

- (void)openFile:(id)sender
{
    eventCaptureButton.enabled = NO;
    [self readyEventCapture];
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel beginSheetModalForWindow:nil completionHandler:^(NSInteger result) {
        if(result == NSFileHandlingPanelOKButton)
        {
            uint32_t size;
            NSData *data;
            NSInteger bytesRead;
            NSEvent *event;
            CGEventRef eventRef;
            uint8_t *buffer;
            BOOL failed = YES;
            NSInputStream *inputStream = [NSInputStream inputStreamWithURL:openPanel.URL];
            [inputStream open];
            
            while(1)
            {
                bytesRead = [inputStream read:(uint8_t *)&size maxLength:sizeof(size)];
                
                if(bytesRead != sizeof(size))
                {
                    failed = (bytesRead != 0);
                    break;
                }
                
                if((buffer = (uint8_t *)malloc(size * sizeof(uint8_t))) == NULL)
                    break;
                
                bytesRead = [inputStream read:buffer maxLength:size];
                
                if(bytesRead != size || (data = [NSData dataWithBytesNoCopy:buffer length:size]) == nil)
                {
                    free(buffer);
                    break;
                }
                
                if((eventRef = CGEventCreateFromData(NULL, (CFDataRef)data)) == NULL)
                    break;
                
                event = [NSEvent eventWithCGEvent:eventRef];
                CFRelease(eventRef);
                
                if(event == nil)
                    break;
                
                [capturedEventsArray addObject:event];
            }
            
            if(failed)
                [capturedEventsArray removeAllObjects];
            
            [inputStream close];
        }
        
        [self showCapturedEvents];
        eventCaptureButton.enabled = YES;
    }];
}

// Text Editing ****************************************************************

- (void)controlTextDidChange:(NSNotification *)notification
{
    if(notification.object == capturedEventsMoreInfoTableView)
        [self showEditedEvent];
    else if(notification.object == eventsFilterTokenField)
        [self eventsFilterTokenFieldTextDidChange];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    if(notification.object == eventByteNumberTextField)
        [self eventByteNumberTextFieldDidEndEditing];
    else if(notification.object == eventsFilterTokenField)
        [self eventsFilterTokenFieldDidEndEditing];
}

@end
