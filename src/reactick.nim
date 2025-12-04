import std/[monotimes, times, macros]
export times

type
  Mutable*[T] = ref object
    value*: T

  TimeControl* = ref object
    scale*: Mutable[float]

  OneShot* = ref object
    body*: proc() {.closure.}
    frame*: uint
    target*: uint
    id*: int

  MultiShot* = ref object
    body*: proc() {.closure.}
    frame*: uint
    target*: uint
    id*: int

  ReacTick* = ref object
    multiShots*: seq[MultiShot]
    oneShots*: seq[OneShot]
    last*: MonoTime
    time*: TimeControl
    previousTime*: TimeControl
    nextId*: int = 0
    fps*: int = 60
    frame*: uint
    frameDuration*: int
    watcherInterval*: int = 1

proc pause*(r: ReacTick) =
  r.previousTime.scale.value = r.time.scale.value
  r.time.scale.value = 0.0

proc resume*(r: ReacTick) =
  r.time.scale.value = r.previousTime.scale.value

proc clear*(reactick: ReacTick) =
  # Clear the closures from the reactick.
  reactick.multiShots.setLen(0)
  reactick.oneShots.setLen(0)

proc genId*(reactick: ReacTick): int =
  # Create an id for the next registered closure.
  result = reactick.nextId
  inc reactick.nextId

proc frameTime*(frames: int): int =
  # Calculate frames per second.
  1_000_000 div frames

proc targetUs*(r: ReacTick): int =
  (r.frameDuration.float / r.time.scale.value).int

template ControlFlow*(f: ReacTick) =
  # Control flow for ticking. Ensures callbacks don't execute until 
  # a frame tick is valid.
  if (getMonoTime() - f.last).inMicroseconds < f.targetUs():
    return

proc tick*(f: ReacTick, controlFlow: bool = true) =
  # Processes callbacks.
  if f.time.scale.value == 0.0:
    return
  if controlFlow:
    f.ControlFlow()

  if f.frame.int > int.high - 2:
    f.frame = 1
  else:
    f.frame += 1

  when defined(profileTick):
    var ranProcs = false
    var startTime = getMonoTime()
  # MultiShots - every
  for i in 0..f.multiShots.high: # maintain execution order
    if i > f.multiShots.high:
      break
    let ms = f.multiShots[i]
    if ms.frame mod ms.target == 0 and ms.frame != 0:
      f.multiShots[i].body()
      if i > f.multiShots.high:
        break
      f.multiShots[i].frame = 1
      when defined(profileTick):
        ranProcs = true
    else:
      f.multiShots[i].frame += 1
          
  # OneShots - after
  var c = 0
  for i in 0..f.oneShots.high: # maintain execution order
    if c > f.oneShots.high:
      break
    let osh = f.oneShots[c]
    if osh.frame mod osh.target == 0 and osh.frame != 0:
      f.oneShots[c].body()
      # Oneshots may remove themselves from the internal sequence
      # Check c against length to skip removal.
      if c > f.oneShots.high:
        when defined(profileTick):
          ranProcs = true
        break
      f.oneShots.delete(c)
      when defined(profileTick):
        ranProcs = true
    else:
      f.oneShots[c].frame += 1
      c += 1

  when defined(profileTick):
    if ranProcs:
      echo "Total Timeframe: ", (getMonoTime() - startTime)

  f.last = getMonoTime()

proc after*(frames: int, body: proc() {.closure}): OneShot =
  # Helper proc for creating OneShot callbacks.
  OneShot(
    target: frames.uint,
    frame: 1,
    body: body,
    id: -1
  )

proc every*(frames: int, body: proc() {.closure.}): MultiShot =
  # Helper proc for creating MultiShot callbacks.
  MultiShot(
    target: frames.uint,
    frame: 1,
    body: body,
    id: -1
  )

proc run*(f: ReacTick, a: OneShot) =
  # Register a OneShot with ReacTick
  a.id = f.genId()
  f.oneShots.add a

proc run*(f: ReacTick, e: MultiShot) =
  # Register a MultiShot with ReacTick
  e.id = f.genId()
  f.multiShots.add e

proc schedule*(f: ReacTick, a: OneShot): int =
  # Same as run, but returns the id you can use to cancel the closure.
  a.id = f.genId()
  f.oneShots.add a
  a.id

proc schedule*(f: ReacTick, e: MultiShot): int =
  # Same as run, but returns the id you can use to cancel the closure.
  e.id = f.genId()
  f.multiShots.add e
  e.id

proc cancel*(f: ReacTick, id: int) =
  # Removes task from ReacTick.
  when defined(debug):
    echo "cancel called with id: ", id
  for i in countdown(f.multiShots.high, 0):
    if f.multiShots[i].id == id:
      f.multiShots.delete(i)
      return
  # Remove from OneShots
  for i in countdown(f.oneShots.high, 0):
    if f.oneShots[i].id == id:
      f.oneShots.delete(i)
      return

proc cancel*(f: ReacTick, ids: var seq[int]) =
  # Batch cancellation. Removes all tasks in the list and clears the list.
  for i in countdown(ids.high, 0):
    f.cancel(ids[i])
  ids.setLen(0)

template cancel*(f: ReacTick): untyped =
  # Cancel from within a ReacTick.cancelable block.
  when defined(debug):
    echo "Canceling ", watcherId, " and ", cbId
  f.cancel(watcherId)
  f.cancel(cbId)

proc nextIds*(f: ReacTick, amount: int = 2): seq[int] =
  # Quick grab ids to cancel. Good for adding multiple task ids to a seq.
  result.add f.nextId
  var startingId = f.nextId
  for i in 1..amount:
    result.add startingId + 1
    startingId += 1

template watch*(f: ReacTick, cond: untyped, m: MultiShot): untyped =
  # Waits until condition is true before scheduling multishot. Cancels
  # multishot once condition is false. Reschedules/cancels based on
  # condition and requires explicit cancellation. 
  # Multishot continues to fire while condition is true.
  var triggered = false
  let cbId = f.genId()
  f.run every(f.watcherInterval) do():  
    if (`cond`) and not triggered:
      # echo "cbId ", cbId
      f.multiShots.add MultiShot(
        target: m.target,
        frame: m.frame,
        body: m.body,
        id: cbId
      )
      triggered = true
    elif not (`cond`) and triggered:
      f.cancel(cbId)
      triggered = false

template watch*(f: ReacTick, cond: untyped, o: OneShot): untyped =
  # Waits until condition is true before scheduling oneshot. Cancels 
  # oneshot if the condition isn't true before the oneshot is 
  # called. Watcher must be canceled explicitly.
  # Oneshot called once per true condition.
  var triggered = false
  let cbId = f.genId()
  f.run every(f.watcherInterval) do():
    if (`cond`) and not triggered:
      f.oneShots.add OneShot(
        target: o.target,
        body: o.body,
        id: cbId,
        frame: o.frame - 1
      )
      triggered = true
    elif not (`cond`) and triggered:
      f.cancel(cbId)
      triggered = false

template `when`*(f: ReacTick, cond: untyped, m: MultiShot): untyped =
  # Triggers multishot when the condition is met. Multishot persists
  # unless canceled explicitly.
  let cbId = f.genId()
  let nid = cbId + 1
  f.run every(f.watcherInterval) do():
    if (`cond`):
      f.multiShots.add MultiShot(
        target: m.target,
        frame: m.frame,
        body: m.body,
        id: cbId
      )
      f.cancel(nid)

template `when`*(f: ReacTick, cond: untyped, o: OneShot): untyped =
  # Triggers oneshot when the condition is met. Since oneshots terminate
  # themselves, no canceling is required.
  let cbId = f.genId()
  var nid = cbId + 1
  f.run every(f.watcherInterval) do():
    if (`cond`):
      f.oneShots.add OneShot(
        target: o.target,
        body: o.body,
        id: cbId,
        frame: o.frame - 1
      )
      f.cancel(nid)

template `while`*(f: ReacTick, cond: untyped, whileIn: untyped, onExit: untyped): untyped =
  var active = false
  f.run every(f.watcherInterval) do():
    let conditionMet = (`cond`)
    if conditionMet:
      active = true
      whileIn
    elif not conditionMet and active:
      active = false
      onExit

template mode*(f: ReacTick, cond: untyped, onEnter: untyped, onExit: untyped): untyped =
  var active = false
  f.run every(f.watcherInterval) do():
    let conditionMet = (`cond`)
    
    if conditionMet and not active:
      active = true
      onEnter
    elif not conditionMet and active:
      active = false
      onExit

template toggle*(f: ReacTick, cond: untyped, action: untyped): untyped =
  var active = false
  f.run every(f.watcherInterval) do():
    let conditionMet = (`cond`)

    if conditionMet and not active:
      active = true
      action
    
    elif not conditionMet:
      active = false

template latch*(f: ReacTick, cond: untyped, action: untyped): untyped =
  var triggered = false
  let cbId = f.callbackId()
  f.run every(f.watcherInterval) do():
    if (`cond`) and not triggered:
      triggered = true
      action
      f.cancel(cbId)

template cooldown*(f: ReacTick, cond: untyped, interval: int, action: untyped): untyped =
  var ready = true
  f.run every(f.watcherInterval) do():
    if (`cond`) and ready:
      action
      ready = false
      f.run after(interval) do():
        ready = true

template reactVar*(f: ReacTick, variable: untyped, body: untyped): untyped =
  var oldValue = `variable`
  f.run every(f.watcherInterval) do():
    let newValue = `variable`
    if newValue != oldValue:
      oldValue = newValue
      let it {.inject.} = newValue
      body

proc mutable*[T](value: T): Mutable[T] =
  result.new()
  result.value = value

proc newReacTick*(fps: int = 60, watcherInterval: int = 1): ReacTick =
  # Create a new ReacTick object!
  var f: ReacTick
  f.new()
  f.fps = fps
  f.frame = 0.uint
  f.multiShots = newSeq[MultiShot]()
  f.oneShots = newSeq[OneShot]()
  f.last = getMonoTime()
  f.nextId = 0
  f.watcherInterval = watcherInterval
  f.time = TimeControl(scale: mutable(1.0))
  f.previousTime = TimeControl(scale: mutable(1.0))
  f.frameDuration = frameTime(f.fps)
  return f

template watcherIds*(f: ReacTick) =
  # Used for the ReacTick.cancel macro.
  var watcherId {.inject.} = f.nextId + 1
  var cbId {.inject.} = f.nextId

proc watcherId*(f: ReacTick): int =
  # Get the Task ID for the watcher.
  f.nextId + 1

proc callbackId*(f: ReacTick): int =
  # Get the Task ID for the callback.
  f.nextId

macro cancelable*(f: ReacTick, x: untyped): untyped =
  # Create a block of watch/when statements that can be easily canceled
  # from within the watch/when block.
  result = newStmtList()
  for statement in x:
    result.add quote do:
      block:
        `f`.watcherIds
        `statement`
  echo result.repr

# === EXAMPLE ===
if isMainModule:
  var clock = ReacTick(fps: 60)

  type 
    Cat = ref object
      name: string
      health: int
      hunger: int
      energy: int
      eating: bool
      learnedToHunt: bool   # A permanent progression flag
      canSwim: bool

  proc newCat(name: string): Cat =
    new result
    result.name = name
    result.health = 100
    result.hunger = 50
    result.energy = 100
    result.eating = false
    result.learnedToHunt = false
    result.canSwim = false

  proc feed(cat: Cat) =
    cat.hunger = max(cat.hunger - 40, 0)
    cat.eating = true
    echo cat.name, " is eating. Hunger now ", cat.hunger

  proc finishedEating(cat: Cat) =
    cat.eating = false
    echo cat.name, " finished eating."

  proc nap(cat: Cat) =
    cat.energy = min(cat.energy + 10, 100)
    echo cat.name, " naps. Energy: ", cat.energy

  proc learnHunting(cat: Cat) =
    cat.learnedToHunt = true
    echo cat.name, " has learned to hunt! (Permanent skill)"

  proc takeWaterDamage(cat: Cat) =
    cat.health -= 10
    echo "Cat taking water damage! Health: ", cat.health

  proc learnToSwim(cat: Cat) =
    cat.canSwim = true
    echo cat.name, " learned to swim!"

  proc inWater(cat: Cat): bool =
    true

  # Create cats
  var scrubs = newCat("Scrubs")
  var shadow = newCat("Shadow")

  # === BASE NEEDS: These are REVERSIBLE → normal watchers ===

  # Hunger gradually increases
  clock.run every(60) do():
    scrubs.hunger = min(scrubs.hunger + 1, 100)
    shadow.hunger = min(shadow.hunger + 1, 100)
    echo "Scrubs hunger: ", scrubs.hunger
    echo "Shadow hunger: ", shadow.hunger

  # Energy gradually decreases
  clock.run every(120) do():
    scrubs.energy = max(scrubs.energy - 1, 0)
    shadow.energy = max(shadow.energy - 1, 0)
    echo "Scrubs energy: ", scrubs.energy
    echo "Shadow energy: ", shadow.energy

  # === HUNGER RESPONSE: Reversible → NOT cancelable ===

  # Meow until fed
  clock.watch scrubs.hunger >= 70, every(90) do():
    echo scrubs.name, " meows! Hunger: ", scrubs.hunger
    if scrubs.hunger >= 90:
      scrubs.feed()

  clock.watch shadow.hunger >= 70, every(90) do():
    echo shadow.name, " meows! Hunger: ", shadow.hunger
    if shadow.hunger >= 90:
      shadow.feed()

  clock.when scrubs.eating, after(120) do():
    scrubs.finishedEating()
    echo "Scrubs finished eating! Scrubs hunger: ", scrubs.hunger

  clock.when shadow.eating, after(120) do():
    shadow.finishedEating()
    echo "Shadow finished eating! Shadow hunger: ", shadow.hunger

  # === ENERGY RESPONSE: Reversible → NOT cancelable ===

  # Nap until fully rested
  clock.watch scrubs.energy <= 90, every(50) do():
    scrubs.nap()
    echo "Scrubs energy: ", scrubs.energy

  clock.watch shadow.energy <= 90, every(50) do():
    shadow.nap()
    echo "Shadow energy: ", shadow.energy

  # === PERMANENT PROGRESSION: This IS cancelable! ===
  clock.cancelable:
    clock.watch scrubs.inWater, every(60) do():
      if scrubs.canSwim:
        clock.cancel() # removes watcher and callback entirely.
      elif scrubs.health <= 80:
        scrubs.learnToSwim()
      else:
        scrubs.takeWaterDamage()

  # === PERMANENT PROGRESSION: Self-canceling! ===
  # Cats will learn to hunt *once* the first time they reach starving condition
  clock.when scrubs.hunger >= 60, after(60) do():
    scrubs.learnHunting()
  clock.when shadow.hunger >= 60, after(60) do():
    shadow.learnHunting()

  # End simulation after 20 ticks
  var t = 0
  clock.run every(60) do():
    t += 1
    if t == 120:
      quit(QuitSuccess)

  while true:
    clock.tick()
