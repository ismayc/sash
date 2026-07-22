import Foundation

print("Running SashKit tests…\n")

runZoneTests()
runLayoutTests()
runGeometryMathTests()
runLayoutStoreTests()
runDisplayNamingTests()
runAutoArrangeTests()
runZoneReflowTests()

exit(T.summarize())
