import Foundation

print("Running SashKit tests…\n")

runZoneTests()
runLayoutTests()
runGeometryMathTests()
runLayoutStoreTests()
runDisplayNamingTests()
runDisplayTargetTests()
runAutoArrangeTests()
runZoneReflowTests()

exit(T.summarize())
