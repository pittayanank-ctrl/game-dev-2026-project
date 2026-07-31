# 2D Platformer Starter Kit

This starter kit provides all the essential mechanics needed to build a complete 2D platformer game in Godot 4.7. It is designed as a hands-on learning resource for students taking the **Computer Game Development** course at the **College of Computing, Khon Kaen University**.

## Preview

<img src="docs/qrcode.png" style="width:300px;" />

- [Game Preview](https://twachi.github.io/2D-Platformer-Starter-Kit/)


## Features

- **Game Menu** — A simple main menu scene (`Menu.tscn`) with Start and Exit options, so players can launch into the game or quit cleanly.
- **Mobile & Web Design** — On-screen touch controls are included, allowing the game to be played on phones, tablets, and browsers without a keyboard.
- **Platformer Controller** — Responsive horizontal movement and jumping with double jump support, configurable directly from the Godot Inspector.
- **Weapon System** — Shoot fireball projectiles with physics-based bouncing and a configurable lifetime. Bullets can defeat enemies and add to the player's score.
- **Enemy AI** — Enemies patrol the level, reverse direction on walls, and detect the player using raycasting. They can be defeated with bullets.
- **Enemy Spawner** — A reusable spawner that generates enemies over time with configurable speed, respawn delay, and maximum instance limits.
- **Animated Player** — Idle, walk, jump, and attack animations driven by state logic; sprite flips automatically based on movement direction.
- **Particle Effects** — Running particle trails, death particles, and damage feedback (red flash) for juicier game feel.
- **Damage & Health System** — Player takes damage on enemy contact with knockback and temporary invincibility frames. HP bar and life count are displayed in the UI.
- **Save & Load** — Save and load game progress (position, score, lives, and settings) using JSON files.
- **Sound & Music Toggle** — Persistent audio settings saved to a config file, with on-screen mute/unmute buttons.
- **Score System** — Collect coins or defeat enemies to increase your score; UI updates in real time through the game manager.
- **Demo Levels** — Two hand-crafted levels that introduce platformer design patterns and progressively challenge the player.
- **Level Management** — Clean scene transitions between levels using an autoload transition manager.
- **Beginner-Friendly Code** — Every script is documented and structured to be easy to read, modify, and extend.

## Getting Started

1. Open the project in [Godot 4.7](https://godotengine.org/) or later.
2. Press **F5** or click **Play** to run the main menu.
3. Use **A/D** or **Left/Right** to move, **Space** to jump, and **X** to shoot.
4. On mobile or web, use the on-screen buttons at the bottom of the screen.
5. Collect coins, defeat enemies, avoid traps, and reach the door to finish each level.

## Project Structure

```
Scenes/
├── Actors/           # Player, enemies, and spawners
├── Levels/           # Level scenes, base level template, and UI
├── Managers/         # GameManager, SceneTransition, AudioManager
└── Prefabs/          # Reusable objects (bullet, coin, potion, door, button)

Assets/
├── Fonts/            # Custom fonts
├── Icons/            # UI icons
├── Sound/            # BGM and SFX
├── Spritesheet/      # Character and tile sprites
└── Textures/         # Particle and effect textures
```

## Controls

| Input | Action |
|-------|--------|
| A / Left Arrow | Move left |
| D / Right Arrow | Move right |
| Space / S | Jump |
| X | Shoot |
| On-screen buttons | Mobile and web touch controls |

## Inspector Tips

- **Player**: Toggle `double_jump` to enable double jump. Adjust `move_speed`, `jump_force`, `shoot_cooldown_time`, and `bullet_lifetime` directly in the inspector.
- **Enemy Spawner**: Configure `enemy_scenes`, `speed_range`, `respawn_time`, and `max_instance` to control enemy behavior and density.
- **Bullet**: Adjust `speed` and `lifetime` to change projectile feel.

## Saving

- Press the **Save** button in the top-right corner to save your progress.
- The game saves the player's position, score, lives, and audio settings.

## Credits

**Original Developer**
- [AdilDevStuff](https://github.com/AdilDevStuff) — [2D-Platformer-Starter-Kit](https://github.com/AdilDevStuff/2D-Platformer-Starter-Kit)

**2D Assets**
- [Kenney.nl](https://www.kenney.nl/)
- [craftpix.net](https://craftpix.net/)
- [Ravenmore](https://ravenmore.itch.io/)
- [Icons8.com](https://icons8.com)

**Sound Effects**
- GDFXR (Sfxr plugin for Godot)

**Modified for Educational Use By**
- College of Computing, Khon Kaen University
