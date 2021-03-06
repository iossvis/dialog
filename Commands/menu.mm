#import <Carbon/Carbon.h>
#import "../Dialog2.h"
#import "../TMDCommand.h"
#import "Utilities/TextMate.h" // -positionForWindowUnderCaret

// ========
// = Menu =
// ========

/*
echo '{ items = ({title = "foo"; header = 1;},{title = "bar";}); }' | "$DIALOG" menu
"$DIALOG" menu --items '({title = "foo"; header = 1;},{title = "bar";})'
*/

@interface DialogPopupMenuTarget : NSObject
@property (nonatomic, retain) NSDictionary* selectedItem;
@end

@implementation DialogPopupMenuTarget
- (BOOL)validateMenuItem:(NSMenuItem*)menuItem
{
	return [menuItem action] == @selector(takeRepresentedObjectFrom:);
}

- (void)takeRepresentedObjectFrom:(NSMenuItem*)sender
{
	NSAssert([sender isKindOfClass:[NSMenuItem class]], @"Unexpected sender for menu target");
	self.selectedItem = [sender representedObject];
}
@end

@interface TMDMenuCommand : TMDCommand
@end

@implementation TMDMenuCommand
+ (void)load
{
	[TMDCommand registerObject:[self new] forCommand:@"menu"];
}

- (NSString *)commandDescription
{
	return @"Presents a menu using the given structure and returns the option chosen by the user";
}

- (NSString *)usageForInvocation:(NSString *)invocation;
{
	return [NSString stringWithFormat:@"\t%1$@ --items '({title = foo;}, {separator = 1;}, {header=1; title = bar;}, {title = baz;})'\n", invocation];
}

- (void)handleCommand:(CLIProxy*)proxy
{
	NSDictionary* args = [proxy parameters];
	NSArray* menuItems = [args objectForKey:@"items"];

	// FIXME this is needed only because we presently can’t express argument constraints (CLIProxy would otherwise correctly validate/convert CLI arguments)
	if([menuItems isKindOfClass:[NSString class]])
		menuItems = [NSPropertyListSerialization propertyListFromData:[(NSString*)menuItems dataUsingEncoding:NSUTF8StringEncoding] mutabilityOption:NSPropertyListImmutable format:nil errorDescription:NULL];

	NSMenu* menu = [[[NSMenu alloc] init] autorelease];
	[menu setFont:[NSFont menuFontOfSize:([[NSUserDefaults standardUserDefaults] integerForKey:@"OakBundleManagerDisambiguateMenuFontSize"] ?: [NSFont smallSystemFontSize])]];
	DialogPopupMenuTarget* menuTarget = [[[DialogPopupMenuTarget alloc] init] autorelease];

	int item_id = 0;
	bool in_section = false;
	for(NSDictionary* menuItem : menuItems)
	{
		if([[menuItem objectForKey:@"separator"] intValue])
		{
			[menu addItem:[NSMenuItem separatorItem]];
		}
		else if([[menuItem objectForKey:@"header"] intValue])
		{
			[menu addItemWithTitle:[menuItem objectForKey:@"title"] action:NULL keyEquivalent:@""];
			in_section = true;
		}
		else
		{
			NSMenuItem* theItem = [menu addItemWithTitle:[menuItem objectForKey:@"title"] action:@selector(takeRepresentedObjectFrom:) keyEquivalent:@""];
			[theItem setTarget:menuTarget];
			[theItem setRepresentedObject:menuItem];
			if(++item_id <= 10)
			{
				[theItem setKeyEquivalent:[NSString stringWithFormat:@"%d", item_id % 10]];
				[theItem setKeyEquivalentModifierMask:0];
			}
			if (in_section)
				[theItem setIndentationLevel:1];
		}
	}

	NSPoint pos = [NSEvent mouseLocation];
	if(id textView = [NSApp targetForAction:@selector(positionForWindowUnderCaret)])
		pos = [textView positionForWindowUnderCaret];
	

	if([menu popUpMenuPositioningItem:nil atLocation:pos inView:nil] && menuTarget.selectedItem)
		[TMDCommand writePropertyList:menuTarget.selectedItem toFileHandle:[proxy outputHandle]];
}
@end
