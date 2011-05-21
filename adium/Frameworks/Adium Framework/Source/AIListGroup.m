/* 
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
 * with this source distribution.
 * 
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIListGroup.h>
#import <Adium/AISortController.h>
#import <AIUtilities/AIArrayAdditions.h>
#import <Adium/AIContactList.h>
#import <Adium/AIListContact.h>
#import <Adium/AIContactHidingController.h>
#import <Adium/AIProxyListObject.h>
#import <Adium/AIUserIcons.h>

#define PREF_GROUP_CONTACT_LIST_DISPLAY		@"Contact List Display"

@interface AIListObject ()
- (void)setContainingGroup:(AIListGroup *)inGroup;
@end

@interface AIListGroup ()
- (void) rebuildVisibleCache;
@end

@implementation AIListGroup

- (id)initWithUID:(NSString *)inUID
{
	if ((self = [super initWithUID:inUID service:nil])) {
		_visibleObjects = [[NSMutableArray alloc] init];
		_containedObjects = [[NSMutableArray alloc] init];
		expanded = YES;
		[[AIContactObserverManager sharedManager] registerListObjectObserver:self];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rebuildVisibleCache) name:CONTACT_VISIBILITY_OPTIONS_CHANGED_NOTIFICATION object:nil];
	}
	
	return self;
}

- (void)dealloc
{
	[_visibleObjects release]; _visibleObjects = nil;
	[_containedObjects release]; _containedObjects = nil;
	[[AIContactObserverManager sharedManager] unregisterListObjectObserver:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[countText release]; countText = nil;
	
	[super dealloc];
}

/* An object ID generated by Adium that is shared by all objects which are, to most intents and purposes, identical to
 * this object.  Ths ID is composed of the service ID and UID, so any object with identical services and object ID's
 * will have the same value here.
 */
- (NSString *)internalObjectID
{
	if (!internalObjectID) {
		internalObjectID = [[AIListObject internalObjectIDForServiceID:@"Group" UID:self.UID] retain];
	}
	return internalObjectID;
}

/*!
 * @brief Generate a special identifier for this group based upon its contents
 *
 * This is useful for storing preferences which are related not to the name of this group (which might be arbitrary) but
 * rather to its contents. The contact list root always returns its own UID, but other groups will have a different 
 * contentsBasedIdentifier depending upon what other objects they contain.
 */
- (NSString *)contentsBasedIdentifier
{
	NSArray *UIDArray = [[_containedObjects valueForKey:@"UID"] sortedArrayUsingSelector:@selector(compare:)];
	NSString *contentsBasedIdentifier = [UIDArray componentsJoinedByString:@";"];
	if (![contentsBasedIdentifier length]) contentsBasedIdentifier = self.UID;

	return contentsBasedIdentifier;
}

- (AIContactList *)contactList
{
	return self.groups.anyObject; //can only have one containing group, its contact list
}

- (void)removeFromGroup:(AIListObject <AIContainingObject> *)group
{
	[adium.contactController removeListGroup:self];
}

#pragma mark Visibility

- (void) rebuildVisibleCache
{
	NSMutableArray *oldVisibleObjects = _visibleObjects;
	
	_visibleObjects = [[NSMutableArray alloc] init];
	for (AIListObject *obj in self)
	{
		if ([[AIContactHidingController sharedController] visibilityOfListObject:obj inContainer:self])
			[_visibleObjects addObject:obj];
	}

	[self didModifyProperties:[NSSet setWithObjects:@"VisibleObjectCount", nil] silent:NO];

	/* Obtain the array of only objects which were previously visible but now are not */
	[oldVisibleObjects removeObjectsInArray:_visibleObjects];
	
	for (AIListObject *obj in oldVisibleObjects) {
		/* For each object which was previously visible but now is not, it's cache clearing time. */

		/* Should be able to remove the proxy object here, but it seemed to cause a crash previously (before fixes
		 * made to the contactObserverManager. Reenable after 1.4.
		 */
		//[obj removeProxyObject:[AIProxyListObject existingProxyListObjectForListObject:obj inListObject:self]];
		[AIUserIcons flushCacheForObject:obj];
	}

	[oldVisibleObjects release];
}

- (NSSet *)updateListObject:(AIListObject *)inObject keys:(NSSet *)inModifiedKeys silent:(BOOL)silent
{
	if (![self containsObject:inObject]) return nil;
	
	NSSet *modifiedProperties = nil;
	if (inModifiedKeys == nil ||
			[inModifiedKeys containsObject:@"isOnline"] ||
			[inModifiedKeys containsObject:@"isIdle"] ||
			[inModifiedKeys containsObject:@"signedOff"] ||
			[inModifiedKeys containsObject:@"signedOn"] ||
			[inModifiedKeys containsObject:@"New Object"] ||
			[inModifiedKeys containsObject:@"VisibleObjectCount"] ||
			[inModifiedKeys containsObject:@"isMobile"] ||
			[inModifiedKeys containsObject:@"IsBlocked"] ||
			[inModifiedKeys containsObject:@"AlwaysVisible"] ||
			[inModifiedKeys containsObject:@"listObjectStatusType"]) {
				
		BOOL shouldBeVisible = [[AIContactHidingController sharedController] visibilityOfListObject:inObject inContainer:self];
		BOOL isVisible = [_visibleObjects containsObject:inObject];
		
		if (shouldBeVisible != isVisible) {
			if (shouldBeVisible) {
				[_visibleObjects addObject:inObject];
			} else {
				[_visibleObjects removeObject:inObject];
			}
			
			[adium.contactController sortListObject:inObject];
			
			modifiedProperties = [NSSet setWithObjects:@"VisibleObjectCount", nil];
			
			if (!shouldBeVisible) {
				/* Should be able to remove the proxy object here, but it seemed to cause a crash previously (before fixes
				 * made to the contactObserverManager. Reenable after 1.4.
				 */
				//[inObject removeProxyObject:[AIProxyListObject existingProxyListObjectForListObject:inObject inListObject:self]];
				[AIUserIcons flushCacheForObject:inObject];
			}
		}
	}
	
	if (modifiedProperties) {
		[self didModifyProperties:modifiedProperties silent:NO];
	}

	return modifiedProperties;
}

- (NSUInteger) visibleCount
{	
	return _visibleObjects.count;
}

/*!
 * @brief Get the visible object at a given index
 */
- (AIListObject *)visibleObjectAtIndex:(NSUInteger)idx
{
	return [_visibleObjects objectAtIndex:idx];
}

- (NSUInteger)visibleIndexOfObject:(AIListObject *)obj
{
	return [_visibleObjects indexOfObject:obj];
}

#pragma mark Object Storage
- (NSArray *)visibleContainedObjects
{
	return [[_visibleObjects copy] autorelease];
}

- (NSArray *)containedObjects
{
	return [[_containedObjects copy] autorelease];
}
- (NSUInteger)countOfContainedObjects
{
    return [_containedObjects count];
}

//Test for the presence of an object in our group
- (BOOL)containsObject:(AIListObject *)inObject
{
	return [_containedObjects containsObject:inObject];
}

//Retrieve an object by index
- (id)objectAtIndex:(NSUInteger)idx
{
    return [_containedObjects objectAtIndex:idx];
}

- (NSArray *)uniqueContainedObjects
{
	return self.containedObjects;
}

//Retrieve a specific object by service and UID
- (AIListObject *)objectWithService:(AIService *)inService UID:(NSString *)inUID
{
	for (AIListObject *object in self) {
		if ([inUID isEqualToString:object.UID] && object.service == inService)
			return object;
	}
	
	return nil;
}

- (BOOL)canContainObject:(id)obj
{
	//todo: enforce metacontacts here, after making all contacts have a containing meta
	return [obj isKindOfClass:[AIListContact class]];
}

/*!
 * @brief Add an object to this group
 *
 * PRIVATE: For contact controller only. Sorting and visible count updating will be performed as needed.
 *
 * @result YES if the object was added (that is, was not already present)
 */
- (BOOL)addObject:(AIListObject *)inObject
{
	NSParameterAssert(inObject != nil);
	NSParameterAssert([self canContainObject:inObject]);
	BOOL success = NO;
	
	if (![_containedObjects containsObjectIdenticalTo:inObject]) {
		//Add the object (icky special casing :( )
		if ([inObject isKindOfClass:[AIListContact class]])
			[(AIListContact *)inObject addContainingGroup:self];
		else
			[inObject setContainingGroup: self];
		
		[_containedObjects addObject:inObject];
		
		/* Sort this object on our own.  This always comes along with a content change, so calling contact controller's
		 * sort code would invoke an extra update that we don't need.  We can skip sorting if this object is not visible,
		 * since it will add to the bottom/non-visible section of our array.
		 */
		if ([[AIContactHidingController sharedController] visibilityOfListObject:inObject inContainer:self]) {
			[_visibleObjects addObject: inObject];
			[self sortListObject:inObject];
		}
		
		[self didModifyProperties:[NSSet setWithObjects:@"VisibleObjectCount", @"ObjectCount", nil] silent:NO];
		
		success = YES;
	}
	
	return success;
}

//Remove an object from this group (PRIVATE: For contact controller only)
- (void)removeObject:(AIListObject *)inObject
{	
	if ([self containsObject:inObject]) {		
		AIListContact *contact = (AIListContact *)inObject;
		//Remove the object
		if ([_visibleObjects containsObject:contact])
			[_visibleObjects removeObject:contact];
		if ([contact.groups containsObject:self])
			[contact removeContainingGroup:self];
		[_containedObjects removeObject:contact];
		

		[self didModifyProperties:[NSSet setWithObjects:@"VisibleObjectCount", @"ObjectCount", nil] silent:NO];
	}
}

- (void)removeObjectAfterAccountStopsTracking:(AIListObject *)inObject
{
	NSParameterAssert([self canContainObject:inObject]);
	if ([_visibleObjects containsObject:inObject])
		[_visibleObjects removeObject:inObject];
	[(AIListContact *)inObject removeContainingGroup:self];
	[_containedObjects removeObject:inObject];
	[self didModifyProperties:[NSSet setWithObjects:@"VisibleObjectCount", @"ObjectCount", nil] silent:NO];	
}

#pragma mark Sorting

//Resort an object in this group (PRIVATE: For contact controller only)
- (void)sortListObject:(AIListObject *)inObject
{
	NSAssert2([_containedObjects containsObject:inObject], @"Attempting to sort %@ in %@ but not contained.", inObject, self);
	
	[_containedObjects moveObject:inObject toIndex:[[AISortController activeSortController] indexForInserting:inObject intoObjects:_containedObjects inContainer:self]];
	if ([_visibleObjects containsObject:inObject])
		[_visibleObjects moveObject:inObject toIndex:[[AISortController activeSortController] indexForInserting:inObject intoObjects:_visibleObjects inContainer:self]];
}

//Resorts the group contents (PRIVATE: For contact controller only)
- (void)sort
{	
	[_containedObjects sortUsingActiveSortControllerInContainer:self];
	[_visibleObjects sortUsingActiveSortControllerInContainer:self];
}

#pragma mark Expanded State

//Set the expanded/collapsed state of this group (PRIVATE: For the contact list view to let us know our state)
- (void)setExpanded:(BOOL)inExpanded
{
	expanded = inExpanded;
	loadedExpanded = YES;
}

//Returns the current expanded/collapsed state of this group
- (BOOL)isExpanded
{
	if (!loadedExpanded) {
		loadedExpanded = YES;
		expanded = [[self preferenceForKey:KEY_EXPANDED group:PREF_GROUP_CONTACT_LIST] boolValue];
	}

	return expanded;
}

- (BOOL)isExpandable
{
	return YES;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)len
{
	return [self.containedObjects countByEnumeratingWithState:state objects:stackbuf count:len];
}

#pragma mark Applescript

- (NSScriptObjectSpecifier *)objectSpecifier
{
	NSScriptClassDescription *containerClassDesc = (NSScriptClassDescription *)[NSScriptClassDescription classDescriptionForClass:[NSApp class]];
	return [[[NSNameSpecifier alloc]
		   initWithContainerClassDescription:containerClassDesc
		   containerSpecifier:nil key:@"contactGroups"
		   name:self.UID] autorelease];
}

- (NSArray *)contacts
{
	return self.containedObjects;
}

- (id)moveContacts:(AIListObject *)contact toIndex:(int)idx
{
	[self moveContainedObject:contact toIndex:idx];
	[adium.contactController sortContactList];
	return nil;
}

//inherit these
@dynamic largestOrder;
@dynamic smallestOrder;
@end