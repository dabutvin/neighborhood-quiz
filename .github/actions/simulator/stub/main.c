// The smallest thing a simulator will install and run. It exists only to be the
// first app on the device, so that installd, dyld and the frameworks the real
// app links are all up and cached before the real app is installed. Linking
// UIKit and SwiftUI without using them is deliberate: loading them is the point.
int main(void) { return 0; }
