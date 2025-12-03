import src/reactick
import unittest2

type 
  TestObj = ref object
    value: int

var clock = newReacTick(fps=60)

proc newTestObj(): TestObj =
  result.new()
  result.value = 0

echo "Starting tests."
var runEvery = newTestObj()
var runAfter = newTestObj()
var scheduleEvery = newTestObj()
var scheduleAfter = newTestObj()
var watchEvery = newTestObj()
var watchAfter = newTestObj()
var whenEvery = newTestObj()
var whenAfter = newTestObj()
var watchEveryC = newTestObj()
var watchAfterC = newTestObj()
var whenEveryC = newTestObj()
var whenAfterC = newTestObj()

suite "Run":
  test "Every":
    # --- Run Every ---
    clock.run every(1) do():
      runEvery.value += 1

    clock.tick(false)
    check clock.multiShots.len == 1
    check runEvery.value == 1

  test "After":
    # --- Run After ---
    clock.run after(1) do():
      runAfter.value += 1

    check clock.oneShots.len == 1
    clock.tick(false)
    check runAfter.value == 1
    check clock.oneShots.len == 0

suite "Schedule":
  test "Every":
    # --- Schedule Every ---
    let schEv = clock.schedule every(1) do():
      scheduleEvery.value += 1

    check schEv == 2
    check clock.multiShots.len == 2
    clock.tick(false)
    check scheduleEvery.value == 1
    clock.cancel(schEv)
    check clock.multiShots.len == 1
  
  test "After":
    # --- Schedule After ---
    let schAf = clock.schedule after(1) do():
      scheduleAfter.value += 1

    check schAf == 3
    check clock.oneShots.len == 1
    clock.tick(false)
    check scheduleAfter.value == 1
    clock.cancel(schAf)
    check clock.oneShots.len == 0

suite "Watch":
  test "Every":
    # --- Watch Every ---
    clock.watch watchEvery.value == 0, every(1) do():
      watchEvery.value += 1

    check clock.multiShots.len == 2
    # trigger evaluation of condition
    clock.tick(false)
    check clock.multiShots.len == 3
    check watchEvery.value == 0
    # trigger callback
    clock.tick(false)
    check watchEvery.value == 1
  
  test "After":
    # --- Watch After ---
    clock.watch watchAfter.value == 0, after(1) do():
      watchAfter.value += 1

    check clock.multiShots.len == 4
    # Evaluate condition
    clock.tick(false)
    check clock.oneShots.len == 1
    check watchAfter.value == 0
    # trigger callback
    clock.tick(false)
    check watchAfter.value == 1

suite "When":
  test "Every":
    # --- When Every ---
    clock.when whenEvery.value == 0, every(1) do():
      whenEvery.value += 1

    check clock.multiShots.len == 4
    # trigger condition / watcher removed.
    clock.tick(false)
    check clock.multiShots.len == 4
    check whenEvery.value == 0
    # trigger callback
    clock.tick(false)
    check whenEvery.value == 1

  test "After":
    # --- When After ---
    clock.when whenAfter.value == 0, after(1) do():
      whenAfter.value += 1

    check clock.multiShots.len == 5
    # trigger condition / watcher removed.
    clock.tick(false)
    check clock.multiShots.len == 4
    check whenAfter.value == 0
    clock.tick(false)
    check whenAfter.value == 1

suite "Cancelable Watch":
  test "Every":
    # --- Cancelable Watch Every ---
    clock.cancelable:
      clock.watch watchEveryC.value > -1, every(1) do():
        watchEveryC.value += 1
        clock.cancel()

    check clock.multiShots.len == 5
    # trigger evaluation of condition
    clock.tick(false)
    check clock.multiShots.len == 6
    check watchEveryC.value == 0
    # trigger callback which removes watcher
    clock.tick(false)
    check watchEveryC.value == 1
    # make sure they're removed
    clock.tick(false)
    clock.tick(false)
    check clock.multiShots.len == 4
    check watchEveryC.value == 1

  test "After":
    # --- Cancelable Watch After ---
    clock.cancelable:
      clock.watch watchAfterC.value == 0, after(1) do():
        watchAfterC.value += 1
        clock.cancel()

    check clock.multiShots.len == 5
    # Evaluate condition
    clock.tick(false)
    check clock.oneShots.len == 1
    check watchAfterC.value == 0
    # trigger callback which removes watcher.
    clock.tick(false)
    check watchAfterC.value == 1
    check clock.oneShots.len == 0
    # make sure they're removed
    clock.tick(false)
    clock.tick(false)
    check clock.multiShots.len == 4
    check clock.oneShots.len == 0
    check watchAfterC.value == 1

suite "Cancelable When":
  test "Every":
    # --- Cancelable When Every ---
    clock.cancelable:
      clock.when whenEveryC.value == 0, every(1) do():
        whenEveryC.value += 1
        clock.cancel()

    check clock.multiShots.len == 5
    # trigger condition / watcher removed.
    clock.tick(false)
    check clock.multiShots.len == 5
    check whenEveryC.value == 0
    # trigger callback which removes callback
    clock.tick(false)
    check whenEveryC.value == 1
    check clock.multiShots.len == 4
    # Make sure they're removed.
    clock.tick(false)
    clock.tick(false)
    check clock.multiShots.len == 4
    check whenEveryC.value == 1
  
  test "After":
    # --- Cancelable When After ---
    clock.cancelable:
      clock.when whenAfterC.value == 0, after(1) do():
        whenAfterC.value += 1
        clock.cancel()

    check clock.multiShots.len == 5
    # trigger condition / watcher removed.
    clock.tick(false)
    check clock.multiShots.len == 4
    check clock.oneShots.len == 1
    check whenAfterC.value == 0
    # trigger callback
    clock.tick(false)
    check clock.multiShots.len == 4
    check clock.oneShots.len == 0
    check whenAfterC.value == 1
    # Make sure it's removed
    clock.tick(false)
    clock.tick(false)
    check whenAfterC.value == 1

var manId = newTestObj()
suite "Getting IDs Manually":
  test "ID Verification Through Cancellation":
    let cb1 = clock.callbackId()
    let wa1 = clock.watcherId()
    clock.watch manId.value == 0, every(1) do():
      manId.value += 1

    check clock.multiShots.len == 5
    clock.tick(false)
    clock.cancel(wa1)
    check clock.multiShots.len == 5
    check manId.value == 0
    clock.tick(false)
    check manId.value == 1
    clock.cancel(cb1)
    check clock.multiShots.len == 4
    clock.tick(false)
    check manId.value == 1

suite "State-Based":
  test "during":
    var duringClock = newReacTick(fps=60)
    var duringObj = newTestObj()
    duringClock.during duringObj.value == 0:
      duringObj.value += 1
    do:
      duringObj.value += 1

    duringClock.tick(false)
    duringClock.tick(false)
    duringClock.tick(false)

    check duringObj.value == 2

  test "pulse":
    var pulseClock = newReacTick(fps=60)
    var pulseObj = newTestObj()
    pulseClock.pulse pulseObj.value == 0:
      pulseObj.value += 1

    pulseClock.tick(false)
    pulseClock.tick(false)
    pulseClock.tick(false)

    check pulseObj.value == 1
    pulseObj.value = 0
    pulseClock.tick(false)
    check pulseObj.value == 1

suite "Timescaling":
  test "Pause / Resume":
    var pauseClock = newReacTick(fps=60)
    var counter = 0
    pauseClock.run every(1) do():
      counter += 1
      if counter == 5 or counter == 15:
        pauseClock.pause()

    while pauseClock.timescale != 0.0:
      pauseClock.tick()

    check counter == 5
    pauseClock.tick(false)
    pauseClock.tick(false)
    
    check counter == 5
    pauseClock.resume()

    pauseClock.tick(false)
    pauseClock.tick(false)
    
    check counter == 7

  test "Correct Timescale":
    var tsClock = newReacTick(fps=60)
    var c = 0
    let cbId = clock.callbackId()
    tsClock.run every(60) do():
      c += 1
      if c == 1:
        echo "2x slower..."
        tsClock.timescale = 0.5
        check tsClock.targetUs() == 33_332
      if c == 6:
        echo "2x faster..."
        tsClock.timescale = 2.0 
        check tsClock.targetUs() == 8_333
      if c == 10:
        tsClock.cancel cbId
      echo c
    while c < 10:
      tsClock.tick()


# Run the sim for 5 seconds.
var t = 0
clock.run every(60) do():
  echo t + 1
  t += 1

for i in 0..clock.multiShots.high:
  clock.multiShots[i].frame = 1

echo "\nRunning sim for 5 seconds..."
while t < 5:
  clock.tick()

suite "Ending States":
  test "MultiShot Count":
    check clock.multiShots.len == 5
    
  test "OneShot Count":
    check clock.oneShots.len == 0

  test "Clear Callbacks":
    clock.clear()
    check clock.multiShots.len == 0
    check clock.oneShots.len == 0

  test "Check Values":
    check runEvery.value == 331
    check runAfter.value == 1
    check scheduleEvery.value == 1
    check scheduleAfter.value == 1
    check watchEvery.value == 1
    check watchAfter.value == 1
    check whenEvery.value == 322
    check whenAfter.value == 1
    check watchEveryC.value == 1
    check watchAfterC.value == 1
    check whenEveryC.value == 1
    check whenAfterC.value == 1
