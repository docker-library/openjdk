@test "package 'java' should be present" {
  run which java
  [ $status -eq 0 ]
}