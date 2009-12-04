
#import <AppKit/AppKit.h>
#import "SUInstaller.h"
#import "SUHost.h"
#import "SUStandardVersionComparator.h"

#include <unistd.h>

@interface TerminationListener : NSObject
{
	const char		*executablePath;
	pid_t			parentProcessId;
	const char		*folderPath;
	NSString		*selfPath;
}

- (void) relaunch;
- (void) install;

@end

@implementation TerminationListener

- (id) initWithExecutablePath:(const char *)execPath parentProcessId:(pid_t)ppid folderPath: (const char*)inFolderPath
		selfPath: (NSString*)inSelfPath
{
	self = [super init];
	if (self != nil)
	{
		ProcessSerialNumber		psn = { 0, kCurrentProcess };
		TransformProcessType( &psn, kProcessTransformToForegroundApplication );
		[[NSApplication sharedApplication] activateIgnoringOtherApps: YES];
		
		executablePath = execPath;
		parentProcessId = ppid;
		folderPath = inFolderPath;
		selfPath = [inSelfPath retain];
		if (getppid() == 1) // ppid is launchd (1) => parent terminated already
			[self install];
		[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(watchdog:) userInfo:nil repeats:YES];
	}
	return self;
}


-(void)	dealloc
{
	[selfPath release];
	selfPath = nil;
	
	[super dealloc];
}


- (void)watchdog:(NSTimer *)timer
{
	ProcessSerialNumber psn;
	if (GetProcessForPID(parentProcessId, &psn) == procNotFound)
		[self install];
}

- (void) relaunch
{
	[[NSWorkspace sharedWorkspace] openFile:[[NSFileManager defaultManager] stringWithFileSystemRepresentation:executablePath length:strlen(executablePath)]];
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
    [[NSFileManager defaultManager] removeFileAtPath: selfPath handler: nil];
#else
	[[NSFileManager defaultManager] removeItemAtPath: selfPath error: NULL];
#endif
	exit(EXIT_SUCCESS);
}


-(void)	install
{
	NSBundle	*theBundle = [NSBundle bundleWithPath: [NSString stringWithUTF8String: executablePath]];
	SUHost		*theHost = [[[SUHost alloc] initWithBundle: theBundle] autorelease];
	
	[SUInstaller installFromUpdateFolder: [NSString stringWithUTF8String: folderPath]
					overHost: theHost
					delegate: self synchronously: YES
					versionComparator: [SUStandardVersionComparator defaultComparator]];
}

- (void)installerFinishedForHost:(SUHost *)aHost
{
	[self relaunch];
}

- (void)installerForHost:(SUHost *)host failedWithError:(NSError *)error
{
	NSRunAlertPanel( @"", @"%@", @"OK", @"", @"", error );
	exit(EXIT_FAILURE);
}

@end

int main (int argc, const char * argv[])
{
	if (argc != 4) return EXIT_FAILURE;
	
	NSString*	selfPath = nil;
	if( argv[0][0] == '/' )
		selfPath = [NSString stringWithUTF8String: argv[0]];
	else
	{
		selfPath = [[NSFileManager defaultManager] currentDirectoryPath];
		selfPath = [selfPath stringByAppendingPathComponent: [NSString stringWithUTF8String: argv[0]]];
	}
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[NSApplication sharedApplication];
	[[[TerminationListener alloc] initWithExecutablePath: argv[1] parentProcessId: atoi(argv[2]) folderPath: argv[3] selfPath: selfPath] autorelease];
	[[NSApplication sharedApplication] run];
	
	[pool drain];
	
	return EXIT_SUCCESS;
}
