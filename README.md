# 🧙‍♂️ Chronomancer ⏱️

> Time is not just a loop—it’s a manipulable dimension of state. Chronomancer lets you reason about it declaratively.

Chronomancer is a frame-based temporal engine for games, simulations, and AI, designed to let you:

* Handle state transitions easily

* Schedule conditional logic

* Bind state to frames declaratively. Snap your game objects to a timeline with Entangled values that automatically update or rewind.

* Rewind, replay, or jump in time. Reverse a time at will or step through frames manually, with deterministic results.

* Keep your code clean and minimal.

Think of it as a *temporal scripting language* embedded in Nim—one library to handle everything from animations to AI state and reversible gameplay.

It gives you:

* Declarative timing
* Reliable sequencing
* Simple cancellation
* AI/state-machine friendly tools (watch, when, cancelable)
* Safe, self-contained closures with captured variables
* Clean logic with no giant update loops or delta-time math

Perfect for:

* Entity AI
* NPC needs and behaviors
* Cooldowns & status effects
* Animation ticks
* Delayed events
* Cutscenes & scripts
* Procedural encounters
* Anything that should happen later, periodically, or based on conditions

Chronomancer makes reactive temporal logic simple. Here's a simple example. 

If a player is in water, but hasn't learned to swim, they should take water damage
every second (assuming 60fps Chronomancer). The following code is all you need 
to toggle water damage on a player that's currently in water. Player enters water, they take damage. Player exits water and they stop taking damage. Once they learn
to swim, this watcher and the associated callback will no longer be checked and the player will no longer take damage in water.

```nim
# More on `clock.cancelable` and `watch` later
clock.cancelable:
  # Player takes damage every second (60fps)
  clock.watch player.inWater, every(60) do():
    if player.canSwim:
      # Watcher/callback unscheduled here
      clock.cancel()
    else:
      player.takeWaterDamage()
```

## ✨ Why Use Frame-Based Scheduling?

Game timing often gets messy:

* Too many if timer > something checks
* Delta-time drift
* Branches everywhere
* Update order bugs
* Losing track of cooldowns or “run this later” logic

`Chronomancer` solves this with:

✔️ Clean declarative scheduling

✔️ Deterministic execution

✔️ Zero delta-time math

✔️ Closures that capture state automatically

✔️ Cancelable tasks (Stop events when entities die)

✔️ Perfect for fixed-step game loops (Nico, SDL, OpenGL, etc.)

You just tell it *when* and *what* to run.

## 📦 Install
`nimble install https://github.com/RattleyCooper/Chronomancer`

## 🚀 Quick Start
```nim
import chronomancer

var clock = newChronomancer(fps=60)

clock.run every(60) do():  # every 1 second at 60fps
  echo "One second passed!"

clock.run after(180) do(): # after 3 seconds
  echo "Three seconds passed!"

while true:
  clock.tick()
```

*Note: `N` must be `>= 1`.*

## 🧠 How Closures Work Here (Important!)

When you write:

```nim
var c = 0
clock.run every(60) do():
  c += 1
```

The `do():` block is a closure, meaning:

* It remembers the variables that were in scope when you created it
* It runs later, but still has access to those variables
* Even if you create many closures, each keeps its own reference of what it captured

That means you can write logic like:

* “Increase this specific cat’s age every second”
* “After 3 seconds rename only this cat”
* “Stop the game after `c` reaches 10”
* “Trigger unique behavior per entity with no global switch statements”

This makes your code *modular*, *clean*, and *expressive*.

Alternatively, you can use a `proc` with the `{.closure.}` pragma.

```nim
var c = 0
proc incC() {.closure.} =
  c += 1

clock.run every(60) incC
```

## 🛠 Core Scheduling Primitives
### `run every(N)` Runs every `N` frames forever.

```nim
clock.run every(120) do():
  enemy.think()
```

### `run after(N)` Runs *once* after `N` frames.

```nim
clock.run after(30) do():
  player.fireReady = true
```

### `schedule` (get a task ID) Useful for cancellation.

```nim
let id = clock.schedule after(300) do(): 
  boss.enrage()
clock.cancel(id)
```

### `watch` Runs callback at desired interval when condition is met.

```nim
clock.cancelable:
  # Player takes damage every second (60fps)
  clock.watch player.inWater, every(60) do():
    if player.canSwim:
      # Watcher/callback unscheduled here
      clock.cancel()
    else:
      player.takeWaterDamage()
```

> Note: `watch` combined with `after` will only execute code *once* while the condition remains `true`, unlike `every` which gives you *repeating* executions *while* the condition remains `true`.

### `when` Schedule a callback once, when a condition is `true`
 
`when` self-destructs the watcher that monitors the condition when the condition becomes `true`. Combining `when` with `every` will create a watcher, but the callback itself will continue running unless canceled explicitly.

`when`/`after` -> Cancels the watcher and the callback automatically.

```nim
# Cats will learn to hunt *once* the first time they reach starving condition
clock.when cat.hunger >= 60, after(60) do():
  cat.learnHunting()
```

`when`/`every` -> Only cancels the watcher.

### `mode` Schedules a watcher with enter/exit behavior

`mode` gives same-frame execution once the condition it's monitoring becomes `true`, and lets you define the exit behavior as well.

```nim
clock.mode player.inSlowMotionZone:
  # On Enter
  clock.timescale = 0.5
do:
  # On Exit
  clock.timescale = 1.0
```

`mode` acts like `watch`, in that it will only run your code **once** per `true` condition. `mode` only runs your exit code **once** per flip to a `false` condition.

## 🛑 Cancellation (Preventing Crashes)

Sometimes you schedule something to happen later (e.g., "Heal player in 3 seconds"), but the entity dies before that happens.

If you don't cancel the task, the closure will still run and try to heal a dead (or nil) player, often causing a crash.

### 🧟 The "Zombie Cat" Problem (Why you need this)

Imagine we schedule a name change for a `cat`, but we delete the `cat` variable before the schedule fires.

```nim
import chronomancer

type Cat = ref object
  name: string

proc newCat(name: string): Cat =
  # Create a new cat.
  result.new()
  result.name = name

var clock = newChronomancer(fps=60)
var scrubs = newCat("Scrubs")

# Schedule a task for the future
# Use 'schedule' instead of 'run' to 
# get the Task ID returned
let renameTask = clock.schedule after(60) do():
  # If 'scrubs' is nil when this runs, the game crashes!
  if scrubs != nil:
    scrubs.name = "Ghost Scrubs" 
    echo "Renamed!"
  else:
    echo "Error: Cat does not exist!"

# Simulate the cat dying/being removed from the game
scrubs = nil 

# If we do NOTHING, the closure runs next second and might crash 
#    or perform logic on an invalid object.

# The Solution: Cancel the task!
clock.cancel(renameTask)

# Now, when we tick, nothing bad happens.
clock.tick()
```

You can use `schedule` to get an ID returned, and `cancel` to stop it, but that's not the only way...

### 🆔 Getting Watcher/Callback IDs Manually

`Chronomancer.watcherId()` -> The id used to cancel the "watchers" reactive primitives like `watch` and `when`. 

Watchers use `Chronomancer.run every(Chronomancer.watcherInterval) do():` to monitor their conditionals, so you need 2 ids(`watcherId` and `callbackId`) to cancel a `watch` or `when` callback.

`Chronomancer.callbackId()` -> The id used to cancel execution of the code you wrote in your callback.

You can get watcher/callback ids by using the `Chronomancer.callbackId()` and/or `Chronomancer.watcherId()` procs to store the ids manually to `cancel` later, or
use the id within a callback explicitly.

> Note: You must call `callbackId`/`watcherId` from OUTSIDE the scope of the callback.

## ✔️👍 Getting Task ID Correctly 
```nim
var clock = newChronomancer(fps=60)

# Get callback id from outside callback scope
let cb1 = clock.callbackId()
clock.run every(60) do():
  # Logic...
  clock.cancel(cb1)
```
## ❌👎 Getting Task ID INCORRECTLY
```nim
var clock = newChronomancer(fps=60)

# INCORRECT! This will lead to 
clock.run every(60) do():
  let cb2 = clock.callbackId()
  # Logic...
  clock.cancel(cb2)
```

### 🎒 The "Bag of Tasks" Pattern

**For entities that might become `nil`**, store all task IDs in a `seq[int]` and `cancel` them all at once:

```nim
type Enemy = ref object
  name: string
  hp: int
  tasks: seq[int]  # Bag of all scheduled task IDs

proc setupEnemy(enemy: Enemy, clock: Chronomancer) =
  # Track enemy state changes to cancel later
  enemy.tasks.add clock.schedule after(600) do():
    enemy.nextState()

proc removeEnemy(enemy: Enemy, clock: Chronomancer) =
  # Cancel ALL tasks with one call and clears their task list.
  clock.cancel(enemy.tasks)
  # Now safe to remove enemy from the game
```

## 👀 Reactive Scheduling with Conditions

(The most powerful part of Chronomancer)

`watch condition, every(N)`

Runs every N frames while condition is true.

Perfect for reversible behaviors:

* “meow until fed”
* “nap until rested”
* “take poison damage while poisoned”
* “regen stamina while resting”

```nim
# Regenerate health if health is ever below 50
clock.watch player.hp < 50, every(30) do():
  player.regen(1)
```

Stops *automatically* when the condition becomes false and *continues* when the condition becomes true again.

`when condition, after(N)`

Schedules a one-shot event that triggers `N` frames after the condition becomes true, then cancels itself.

Great for permanent “unlock once” events:

* learn a skill
* trigger a cutscene
* evolve a creature
* apply a debuff once

```nim
clock.when enemy.hp <= 0, after(1) do():
  enemy.die() # presumably canceling tasks in enemy.die()
```

| API | Runs  | Repeats? | Stops automatically? | Returns Task ID | Task Id Needed to Cancel |
| --- | ----- | -------- | -------------------- | --- | --- |
| `run every(N)`| Every N frames |✔️|❌|❌| `callbackId` |
| `run after(N)`| Once |❌|✔️|❌| `callbackId` |
| `schedule every(N)` | Every N frames |✔️|❌|✔️| Use Returned |
| `schedule after(N)` | Once  | ❌  | ✔️  |✔️| Use Returned |
| `watch cond, every(N)` | Every N frames *while cond is true* |✔️|✔️ (until cond true again) |❌| `watcherId` & `callbackId` |
| `watch cond, after(N)` | Once N frames *when cond* is true |❌|✔️ (util cond true again)|❌| `watcherId` & `callbackId` |
| `when cond, every(N)` | Every N frames `after` condition is true | ❌/✔️ ***Callback* repeats** | ✔️/❌ ***Watcher* self-cancels** | ❌ | `watcherId` & `callbackId` |
| `when cond, after(N)`| Once |❌| ✔️ **Always self-cancels**|❌| `watcherId` & `callbackId` |
| `mode` | `every(Chronomancer.watcherInterval)` | ✔️ | ❌ | ❌ | `callbackId` |


## 🔒 Cancelable Blocks

Sometimes you want a whole block of watchers and tasks to be removed permanently after some condition succeeds. You can use the `Chronomancer.cancelable` block to enable `Chronomancer.cancel()` without needing to pull in the `watcherId` or `callbackId` manually.

Use:

```nim
clock.cancelable:
  # all tasks created here can be individually 
  # canceled with `cancel` within their closure.
  clock.watch something, every(30) do():
    if done:
      # Removes the watcher / callback
      clock.cancel() 

  clock.watch somethingElse, every(30) do():
    if done:
      # Removes the watcher / callback
      clock.cancel()
```

This is ideal for:

* skill learning
* progression gates
* temporary states
* “burn out” or “fleeing” AI
* multi-step interactions

> *Examples in readme.*

`Chronomancer.cancelable` does something under the hood using macros.

This code:

```nim
clock.cancelable:
  clock.watch scrubs.inWater, every(60) do():
    if scrubs.canSwim:
      clock.cancel()
    elif scrubs.health <= 80:
      scrubs.learnToSwim()
    else:
      scrubs.takeWaterDamage()
```

Gets transformed into this code:

```nim
# Creates a local scope.
block:
  # Pulls in ids that will be used for the
  # closures.
  var watcherId = clock.nextId + 1
  var cbId = clock.nextId
  clock.watch scrubs.inWater, every(60)do :
    if scrubs.canSwim:
      # Uses IDs to unschedule the closures.
      clock.cancel(watcherId)
      clock.cancel(cbId)
    elif scrubs.health <= 80:
      scrubs.learnToSwim()
    else:
      scrubs.takeWaterDamage()
```

## 🧩 Patterns & Usage

### `watch every(N)`

### ✅ Example: Taking Damage While Standing in Hazardous Water

Whenever a player is standing in toxic water, they should take damage every 1 second.
When they step out, the damage should immediately stop.
If they step back in, the cycle restarts.

That is exactly:

```nim
clock.watch player.inToxicWater, every(60):
  player.takeDamage 5
```

Player steps into toxic water → `inToxicWater` becomes `true`

Clock starts running the callback every 1 second:

1s → takeDamage(5)

2s → takeDamage(5)

3s → takeDamage(5)
...

1. Player stays in toxic water
2. Damage keeps repeating every second.
3. Player steps out of toxic water → condition becomes false
4. The repeating callback stops immediately.
5. Player steps back into toxic water later
6. The repeating schedule starts again.

Simply:

* Condition turning `true` → schedule the ***repeating*** action
* Condition staying `true` → ***keep repeating***
* Condition turning `false` → cancels the pending trigger
* Condition becoming `true` again → schedule again

### `watch after(N)`

### ✅ Example: Charge-Up Buff When Standing Still

A player gains a focus buff if they stand still for 3 seconds, but the buff should not re-apply every 3 seconds as long as they stay still.

That’s exactly:

```nim
clock.watch player.isStandingStill, after(180):
  player.applyBuff Focus
```

1. Player stops moving → `isStandingStill` becomes `true`
2. Clock waits 3 seconds
3. Buff is applied once
4. Player continues standing still → no retrigger
5. Buff only retriggers after the player moves again and stops again

Simply:

* Condition turning `true` → schedule the ***delayed*** action
* Condition staying `true` → do nothing
* Condition turning `false` → cancels the pending trigger
* Condition becoming `true` again → schedule again

### `when after(N)`

Use `when after(N)` for:

* achievements
* permanent skill unlocks
* “do this once when X becomes true”
* cutscene triggers
* Self-canceling.

`when` is great for non-repeating conditional behavior.

### ✔ Temporary States → `cancelable`:

Use cancelable blocks when you want a state machine step that *eventually* ends forever.

Example: *"learning to swim”*:

* cat enters water
* take damage
* eventually learns
* damage behavior never runs again

### `mode`

### ✅ Example: Use `mode` to scale time in "slow-mo zone"

`Chronomancer` lets you change the speed of your game logic dynamically, allowing for "bullet-time", dynamic difficulty, or changing simulation speeds:

```nim
var clock = newChronomancer(fps=60)

# Slow motion
clock.timescale = 0.5  # Half speed

# 2x speed
clock.timescale = 2.0  # Double speed

# Pause
clock.timescale = 0.0  # Frozen

# Normal
clock.timescale = 1.0  # Default
```

`mode` is useful in situations where `watch` would be overkill. `mode` sets up a watcher that will monitor a condition once per tick, and execute your entry and exit code in the same watcher.

```nim
clock.mode player.inSlowMotionZone:
  # On Enter, go into slow motion
  clock.timescale = 0.5
do:
  # On Exit, return to normal speed
  clock.timescale = 1.0
```


## 🐈 Full Example

```nim
if isMainModule:
  # The fps value defines your logical update 
  # rate. every(60) means ‘every 60 logical 
  # frames’, not real-time seconds.
  var clock = newChronomancer(fps=60)

  type 
    Cat = ref object
      name: string
      health: int
      hunger: int
      energy: int
      eating: bool
      learnedToHunt: bool # A permanent progression flag
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

  # === BASE NEEDS ===
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

  # === HUNGER RESPONSE: NOT cancelable ===
  # Meow until fed
  clock.watch scrubs.hunger >= 70, every(90) do():
    echo scrubs.name, " meows! Hunger: ", scrubs.hunger
    if scrubs.hunger >= 90:
      scrubs.feed()

  clock.watch shadow.hunger >= 70, every(90) do():
    echo shadow.name, " meows! Hunger: ", shadow.hunger
    if shadow.hunger >= 90:
      shadow.feed()

  clock.watch scrubs.eating, after(120) do():
    scrubs.finishedEating()
    echo "Scrubs finished eating! Scrubs hunger: ", scrubs.hunger

  clock.watch shadow.eating, after(120) do():
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

  # === PERMANENT PROGRESSION: This is explicitly cancelable! ===
  clock.cancelable:
    # Is scrubs in water? Let's teach him how to swim.
    clock.watch scrubs.inWater, every(60) do():
      if scrubs.canSwim:
        # removes watcher and callback entirely.
        # this watch block will no longer monitor
        # and it's callback will never fire again.
        # Scrubs is now safe in water!
        clock.cancel() 
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

  # End simulation after 120 seconds
  var t = 0
  clock.run every(60) do():
    t += 1
    if t == 120:
      quit(QuitSuccess)

  while true:
    clock.tick()

```

## ⏱️ About Delta-Time (Do You Need It?)

`Chronomancer` does not use delta-time internally — and it doesn’t need to.

Why?

Because `Chronomancer` is not a game loop or physics integrator.

It’s simply:

A tiny scheduler that runs closures after or every N frames.

It doesn’t care what you use your frames for:

* Rendering
* Physics
* AI updates
* Scripted events
* Gameplay timers
* Cooldowns
* Cutscenes
* Anything else

Your frame loop could be tied to rendering, but it doesn't have to be.

## ❌ When Delta-Time Is Not Needed

* If you are only using `Chronomancer` as:
* a scheduler
* a timed-event system
* a frame-based sequencer

then no delta-time math is required at all.

It’s intentionally simple:

```nim
clock.run after(180) do(): # run this after 180 frames
clock.run every(60) do():     # run this every 60 frames
```

That’s it.

## ✔ When Delta-Time Is Useful (Outside This Library)

If your game or program has variable framerate and you want:

* consistent player movement
* physics updates
* interpolation
* velocity-based animations

Then you might want dt in your game loop.

Example:

```nim
let dt = elapsedTimeSeconds()
player.x += player.speed * dt
```

This is completely separate from how you use the scheduler.
