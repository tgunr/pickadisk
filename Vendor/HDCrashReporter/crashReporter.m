//
//  HDCrashReporter.m
//
//  HDCrashReporter is a framework to send back to the developer the crash reports 
//  and the console log after a crash.
//  Copyright (C) 2006 Humble Daisy
//
//  This library is free software; you can redistribute it and/or
//  modify it under the terms of the GNU Lesser General Public
//  License as published by the Free Software Foundation; either
//  version 2.1 of the License, or (at your option) any later version.
//
//  This library is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
//  Lesser General Public License for more details.
//
//  You should have received a copy of the GNU Lesser General Public
//  License along with this library; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
//
//  For more information contact: developers@profcast.com
//

#import "crashReporter.h"
#import <Message/NSMailDelivery.h>
#import <AddressBook/AddressBook.h>



@implementation HDCrashReporter
- (void) windowDidLoad
{
  [self setSendConsoleLog: YES];
  [self setSendCrashReport: YES];
  [self setShowDetails: NO];
  [self setComments: [[[NSAttributedString alloc] initWithString: @""] autorelease]];
}

+ (BOOL) newCrashLogExists
{
  BOOL returnValue = NO;
  
  //do crash recovery
  //
  NSDate *lastCrashDate = [[NSUserDefaults standardUserDefaults] valueForKey: @"HDCrashReporter.lastCrashDate"];
  NSArray *libraryDirectories = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask,FALSE);
  
  NSString *logFilePathAndname = [NSString stringWithFormat: @"Logs/CrashReporter/%@.crash.log", [self applicationName]];
  NSString *crashLogPath = [[[libraryDirectories objectAtIndex: 0 ] stringByAppendingPathComponent: logFilePathAndname] stringByExpandingTildeInPath];
  
  NSDate *crashLogModificationDate = [[[NSFileManager defaultManager] fileAttributesAtPath: crashLogPath
                                                                              traverseLink: YES] fileModificationDate];
  if (lastCrashDate && 
      crashLogModificationDate && 
      ([crashLogModificationDate compare: lastCrashDate] == NSOrderedDescending))
  {
    //we had a new crash since last time, ask the user ih wants to submit it
    //
    returnValue = YES;
  }
  
  [[NSUserDefaults standardUserDefaults] setValue: crashLogModificationDate
                                           forKey: @"HDCrashReporter.lastCrashDate"];
  
  return returnValue;
}

+ (void) doCrashSubmitting
{ 
  //instantiate our object
  //
  HDCrashReporter *crashReporterController = [[HDCrashReporter alloc] initWithWindowNibName: @"crashReporter"];
  
  //get the crash log
  //
  [crashReporterController setCrashReportData: [[[NSAttributedString alloc] initWithString: [self lastCrashReport]] autorelease]]; 
  
  //now get the console lo
  //  
  [crashReporterController setConsoleLogReport: [[[NSAttributedString alloc] initWithString: [self consoleLog]] autorelease]]; 
  
  [crashReporterController showWindow: self];
}

- (IBAction) sendReport: (id) sender
{   
  [[self window] makeFirstResponder: nil];
  
  [self setIsSending: YES];
  
  //present the sheet
  //
  [[NSApplication sharedApplication] beginSheet: sendingPanel
                                 modalForWindow: [self window]
                                  modalDelegate: self
                                 didEndSelector: nil
                                    contextInfo: nil];
  
  NSString *subjectString = @"crash report";
  
  NSString *email = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"crashReporterEmail"];
  
  if (!email)
    email = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"crashReporterEmail"];
  
  if (!email)
    NSLog (@"crash reported: did not find email address");

  NSMutableAttributedString *emailBody = [[self comments] mutableCopy];
  
  if ([self sendCrashReport])
  {
    NSFileWrapper *attachmentWrapper = [[self crashReportData] fileWrapperFromRange: NSMakeRange(0, [[self crashReportData] length])
                                                                 documentAttributes: [NSDictionary dictionaryWithObject: NSPlainTextDocumentType 
                                                                                                                 forKey: NSDocumentTypeDocumentAttribute]
                                                                              error: nil];
    
    [attachmentWrapper setPreferredFilename: @"crashReport.crash.log"];
    
    //add it to the email body
    //
    [emailBody appendAttributedString: [NSAttributedString attributedStringWithAttachment: [[NSTextAttachment alloc] initWithFileWrapper: attachmentWrapper]]];
  }
  
  if ([self sendConsoleLog])
  {
    
    NSFileWrapper *attachmentWrapper = [[self consoleLogReport] fileWrapperFromRange: NSMakeRange(0, [[self consoleLogReport] length])
                                                                  documentAttributes: [NSDictionary dictionaryWithObject: NSPlainTextDocumentType forKey: NSDocumentTypeDocumentAttribute]
                                                                               error: nil];
    [attachmentWrapper setPreferredFilename: @"console.log"];
    
    //add it to the email body
    //
    [emailBody appendAttributedString: [NSAttributedString attributedStringWithAttachment: [[NSTextAttachment alloc] initWithFileWrapper: attachmentWrapper]]];
  } 
  
  BOOL result = NO;	
  if ([NSMailDelivery hasDeliveryClassBeenConfigured] && email)
  {  
    ABPerson *myself = [[ABAddressBook sharedAddressBook] me];  
    int emailIndex = [[myself valueForProperty: kABEmailProperty] indexForIdentifier: [[myself valueForProperty: kABEmailProperty] primaryIdentifier]]; 
    
    //create the message
    //
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    [headers setObject: [[myself valueForProperty: kABEmailProperty] valueAtIndex: emailIndex] forKey:@"From"];
    [headers setObject: email forKey:@"To"];
    [headers setObject: subjectString forKey:@"Subject"];
    [headers setObject: @"Apple Message" forKey:@"X-Mailer"];
    [headers setObject: @"multipart/mixed" forKey:@"Content-Type"];
    [headers setObject: @"1.0" forKey:@"Mime-Version"];
    
    result = [NSMailDelivery deliverMessage: emailBody
                                    headers: headers
                                     format: NSMIMEMailFormat
                                   protocol: NSSMTPDeliveryProtocol];
  }
  else if (email)
  {
    // Try using NSURL
    //
    NSString *encodedURLString = [[NSString stringWithFormat:@"mailto:%@?SUBJECT=%@&BODY=%@",
      email, subjectString, [emailBody string]] stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
    
    if (encodedURLString)
      result = [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: encodedURLString]];
  }
  
  //close the sending panel
  //
  [[NSApplication sharedApplication] endSheet: sendingPanel];
  [sendingPanel orderOut: self];
  [self setIsSending: NO];
  
  //if not sent, no big deal, just fail silently
  [self close];
}

- (IBAction) showDetails: (id) sender
{
  NSRect windowFrame = [[self window] frame];
  
  if ([sender intValue])
  {
    windowFrame.size = NSMakeSize(480, 581);
    windowFrame.origin.y -= 399;
    [[self window] setFrame: windowFrame
                    display: YES
                    animate: YES];
    [self setShowDetails: [sender intValue]];
  }
  else
  {
    [self setShowDetails: [sender intValue]];
    windowFrame.size = NSMakeSize(480, 182);
    windowFrame.origin.y += 399;
    [[self window] setFrame: windowFrame
                    display: YES
                    animate: YES];
  }
}

#pragma mark ----=accessors=----
//=========================================================== 
//  sendCrashReport 
//=========================================================== 
- (BOOL)sendCrashReport
{
  //NSLog(@"in -sendCrashReport, returned sendCrashReport = %@", sendCrashReport ? @"YES": @"NO" );
  
  return sendCrashReport;
}

- (void)setSendCrashReport:(BOOL)flag
{
  //NSLog(@"in -setSendCrashReport, old value of sendCrashReport: %@, changed to: %@", (sendCrashReport ? @"YES": @"NO"), (flag ? @"YES": @"NO") );
  
  sendCrashReport = flag;
}

//=========================================================== 
//  sendConsoleLog 
//=========================================================== 
- (BOOL)sendConsoleLog
{
  //NSLog(@"in -sendConsoleLog, returned sendConsoleLog = %@", sendConsoleLog ? @"YES": @"NO" );
  
  return sendConsoleLog;
}

- (void)setSendConsoleLog:(BOOL)flag
{
  //NSLog(@"in -setSendConsoleLog, old value of sendConsoleLog: %@, changed to: %@", (sendConsoleLog ? @"YES": @"NO"), (flag ? @"YES": @"NO") );
  
  sendConsoleLog = flag;
}

//=========================================================== 
//  showDetails 
//=========================================================== 
- (BOOL)showDetails
{
  //NSLog(@"in -showDetails, returned showDetails = %@", showDetails ? @"YES": @"NO" );
  
  return showDetails;
}

- (void)setShowDetails:(BOOL)flag
{
  //NSLog(@"in -setShowDetails, old value of showDetails: %@, changed to: %@", (showDetails ? @"YES": @"NO"), (flag ? @"YES": @"NO") );
  
  showDetails = flag;
}

//=========================================================== 
//  crashReportData 
//=========================================================== 
- (NSAttributedString *)crashReportData
{
  //NSLog(@"in -crashReportData, returned crashReportData = %@", crashReportData);
  
  return [[crashReportData retain] autorelease]; 
}

- (void)setCrashReportData:(NSAttributedString *)aCrashReportData
{
  //NSLog(@"in -setCrashReportData:, old value of crashReportData: %@, changed to: %@", crashReportData, aCrashReportData);
  
  if (crashReportData != aCrashReportData) {
    [crashReportData release];
    crashReportData = [aCrashReportData retain];
  }
}

//=========================================================== 
//  consoleLogReport 
//=========================================================== 
- (NSAttributedString *)consoleLogReport
{
  //NSLog(@"in -consoleLogReport, returned consoleLogReport = %@", consoleLogReport);
  
  return [[consoleLogReport retain] autorelease]; 
}

- (void)setConsoleLogReport:(NSAttributedString *)aConsoleLogReport
{
  //NSLog(@"in -setConsoleLogReport:, old value of consoleLogReport: %@, changed to: %@", consoleLogReport, aConsoleLogReport);
  
  if (consoleLogReport != aConsoleLogReport) {
    [consoleLogReport release];
    consoleLogReport = [aConsoleLogReport retain];
  }
}

//=========================================================== 
//  comments 
//=========================================================== 
- (NSAttributedString *)comments
{
  //NSLog(@"in -comments, returned comments = %@", comments);
  
  return [[comments retain] autorelease]; 
}

- (void)setComments:(NSAttributedString *)aComments
{
  //NSLog(@"in -setComments:, old value of comments: %@, changed to: %@", comments, aComments);
  
  if (comments != aComments) {
    [comments release];
    comments = [aComments retain];
  }
}

//=========================================================== 
//  isSending 
//=========================================================== 
- (BOOL)isSending
{
  //NSLog(@"in -isSending, returned isSending = %@", isSending ? @"YES": @"NO" );
  
  return isSending;
}

- (void)setIsSending:(BOOL)flag
{
  //NSLog(@"in -setIsSending, old value of isSending: %@, changed to: %@", (isSending ? @"YES": @"NO"), (flag ? @"YES": @"NO") );
  
  isSending = flag;
}

- (NSString*) companyName
{
  NSString *companyName = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"crashReporterCompanyName"];
  
  if (!companyName)
    companyName = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"crashReporterCompanyName"];
  
  return companyName;
}

+ (NSString*) applicationName
{
  NSString *applicationName = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"CFBundleExecutable"];
  
  if (!applicationName)
    applicationName = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleExecutable"];
  
  return applicationName;
}

- (NSString*) applicationName
{
  return [[self class] applicationName];
}

+ (NSString*) consoleLog
{
  NSString *consolelogPath = [NSString stringWithFormat: @"/Library/Logs/Console/%@/console.log", [NSNumber numberWithUnsignedInt: getuid()]];
  NSString *console = [NSString stringWithContentsOfFile: consolelogPath];
  NSEnumerator *theEnum = [[console componentsSeparatedByString: @"\n"] objectEnumerator];
  NSString* currentObject;
  NSMutableArray *profcastStrings = [NSMutableArray array];
  
  while (currentObject = [theEnum nextObject])
  {
    NSString *keyString = [NSString stringWithFormat: @"%@[", [self applicationName]];
    if ([currentObject rangeOfString: keyString].location != NSNotFound)
      [profcastStrings addObject: currentObject];
  }  
  
  return [profcastStrings componentsJoinedByString: @"\n"];
}

+ (NSString*) lastCrashReport
{
  NSArray *libraryDirectories = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask,FALSE);
  
  NSString *logFilePathAndname = [NSString stringWithFormat: @"Logs/CrashReporter/%@.crash.log", [self applicationName]];
  NSString *crashLogPath = [[[libraryDirectories objectAtIndex: 0 ] stringByAppendingPathComponent: logFilePathAndname] stringByExpandingTildeInPath];
  
  //get the crash
  //
  NSString *crashLogs = [NSString stringWithContentsOfFile: crashLogPath];
  NSString *lastCrash = [[crashLogs componentsSeparatedByString: @"**********\n\n"] lastObject];
  
  return lastCrash; 
}

//=========================================================== 
// dealloc
//=========================================================== 
- (void)dealloc
{
  [self setCrashReportData:nil];
  [self setConsoleLogReport:nil];
  [self setComments:nil];
  
  [super dealloc];
}

@end
