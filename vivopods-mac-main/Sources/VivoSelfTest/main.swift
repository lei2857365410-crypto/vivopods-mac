import Foundation

print("vivo TWS 协议自测")
print(String(repeating: "═", count: 46))

runClassicEncodeChecks()
runGattEncodeChecks()
runRealCaptureChecks()
runMultiConnectChecks()
runMultiConnectControlChecks()
runDecoderChecks()
runBatteryChecks()
runBatteryDisplayChecks()
runBatteryCacheChecks()
runNoiseChecks()
runHandshakeChecks()

exit(Check.summary())
