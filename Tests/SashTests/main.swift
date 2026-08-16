import Foundation

print("Running SashKit tests…\n")

runZoneTests()
runLayoutTests()
runGeometryMathTests()
runLayoutStoreTests()
runDisplayNamingTests()
runDisplayTargetTests()
runScreenMarginsTests()
runAutoArrangeTests()
runAutoArrangeScopeTests()
runZoneReflowTests()

exit(T.summarize())
