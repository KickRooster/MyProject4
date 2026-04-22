# MyProject4 - 2D Action Game (Katana ZERO style)

## How to set up on a new machine

### Prerequisites
- Unreal Engine 5.7
- Game Animation Sample (download from Epic Launcher)

### Steps
1. Create a new project from the **Third Person** template, name it `MyProject4`
2. Open **Game Animation Sample** project in UE editor
3. Migrate the following from Game Animation Sample to MyProject4:
   - `SandboxCharacter_CMC` (the character blueprint + all dependencies)
   - `Variant_Sandbox` folder contents
   - `AC_TraversalLogic` component and related assets
   - `LevelBlock_Traversable` and related Traversal assets
4. Clone this repo into the MyProject4 root directory (overwrite existing files)
5. Enable these plugins in the editor: `AnimationWarping`, `AnimationLocomotionLibrary`, `Chooser`, `PoseSearch`, `MotionWarping`
6. Compile C++ and restart the editor

### What this repo contains (incremental changes only)
- `Source/` — All C++ source code (SandboxCharacterBase with Wall Jump, Coyote Time, Double Jump, Combo Attack)
- `MyProject4.uproject` — Plugin dependencies
- `Content/Blueprints/SandboxCharacter_CMC` — Reparented to C++ base, modified EventGraph
- `Content/Input/IMC_Sandbox` — WASD remapped for 2D side-scrolling
- `Content/Variant_SideScrolling/Lvl_SideScrolling` — Test level
