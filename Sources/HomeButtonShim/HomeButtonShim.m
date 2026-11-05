#import <Foundation/Foundation.h>
#import <GameController/GameController.h>

// Older nxnative hosts do not opt out of macOS's HOME system gesture. Because the preference of
// the foreground process wins, Switch Launcher cannot correct it from the background. This dylib
// is injected by the launcher and makes the same request newer nxnative hosts make themselves.
static void SLKeepHomeButton(GCController *controller) {
    GCControllerButtonInput *home = controller.extendedGamepad.buttonHome;
    if (home) home.preferredSystemGestureState = GCSystemGestureStateDisabled;
}

__attribute__((constructor))
static void SLInstallHomeButtonCompatibility(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (GCController *controller in GCController.controllers) SLKeepHomeButton(controller);
        [NSNotificationCenter.defaultCenter
            addObserverForName:GCControllerDidConnectNotification
            object:nil
            queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *note) {
                SLKeepHomeButton((GCController *)note.object);
            }];
        fprintf(stderr, "[switch-launcher] controller HOME compatibility active\n");
    });
}
