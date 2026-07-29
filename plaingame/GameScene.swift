//
//  GameScene.swift
//  plaingame
//
//  SpriteKit port of "Jason's Game" (originally a Three.js side-scroller).
//  Gameplay, physics constants and collision math mirror the original main.js
//  so the game plays the same; rendering is 2D SpriteKit.
//

import SpriteKit

#if canImport(UIKit)
import UIKit
#endif

final class GameScene: SKScene {

    // MARK: - World scale
    /// Points per "world unit". The original game works in small world units
    /// (player is 1.8 x 2.4). We keep all physics in world units and multiply
    /// by `S` only when positioning/sizing nodes.
    private let S: CGFloat = 40

    // MARK: - Difficulty
    enum Difficulty { case easy, medium, hard }
    private var difficulty: Difficulty = .medium
    private var moveSpeed: CGFloat = 0.2
    private var barrelMinSpeed: CGFloat = 0.15
    private var barrelMaxSpeed: CGFloat = 0.25
    private var barrelSpawnIntervalMs: Double = 120 * 8

    private func applyDifficulty(_ level: Difficulty) {
        difficulty = level
        switch level {
        case .easy:
            moveSpeed = 0.15; barrelMinSpeed = 0.10; barrelMaxSpeed = 0.18; barrelSpawnIntervalMs = 180 * 8
        case .hard:
            moveSpeed = 0.28; barrelMinSpeed = 0.22; barrelMaxSpeed = 0.32; barrelSpawnIntervalMs = 70 * 8
        case .medium:
            moveSpeed = 0.2; barrelMinSpeed = 0.15; barrelMaxSpeed = 0.25; barrelSpawnIntervalMs = 120 * 8
        }
    }

    // MARK: - Physics constants (world units)
    private let jumpStrength: CGFloat = 0.5
    private let gravity: CGFloat = -0.02

    /// How far above the player the camera centers (world units).
    private let camOffsetY: CGFloat = 3
    /// Minimum slice of the world always kept on screen (world units). The
    /// camera zooms out when a viewport is too short/narrow to show this much,
    /// so the ground never falls off the bottom in landscape or on macOS.
    private let minVisibleWidthUnits: CGFloat = 12
    private let minVisibleHeightUnits: CGFloat = 16

    // MARK: - Player state
    private var playerX: CGFloat = -35
    private var playerY: CGFloat = 1
    private var velX: CGFloat = 0
    private var velY: CGFloat = 0
    private var canJump = false
    private var facingRight = true
    private var lastDirectionRight = true

    // Input flags
    private var moveLeft = false
    private var moveRight = false
    private var moveDown = false

    // Animation
    private var currentAnim = "idle"
    private var animFrame = 0
    private var animFrameTime = 0
    private let animFrameRate = 8

    // MARK: - Game flow
    private var started = false
    private var gamePaused = false
    private var playerRespawning = false
    private var won = false

    // MARK: - Nodes
    private let cam = SKCameraNode()
    private var player: SKSpriteNode!
    private var plane: SKSpriteNode?
    private var badGuy: SKSpriteNode?
    private let worldNode = SKNode()

    // Static level geometry (world units)
    private struct Ground { let x: CGFloat; let w: CGFloat }
    private struct Platform { let x: CGFloat; let y: CGFloat }
    private var grounds: [Ground] = []
    private var platforms: [Platform] = []
    private var obstacles: [CGPoint] = []
    private var lastPlatformX: CGFloat = 0

    // Dynamic objects
    private final class Barrel {
        let node: SKShapeNode; var x: CGFloat; var y: CGFloat; var vx: CGFloat; var vy: CGFloat; var bouncing: Bool
        init(node: SKShapeNode, x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, bouncing: Bool) {
            self.node = node; self.x = x; self.y = y; self.vx = vx; self.vy = vy; self.bouncing = bouncing
        }
    }
    private final class Bomb {
        let node: SKSpriteNode; var x: CGFloat; var y: CGFloat; var vx: CGFloat; var vy: CGFloat; var hit = false
        init(node: SKSpriteNode, x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat) {
            self.node = node; self.x = x; self.y = y; self.vx = vx; self.vy = vy
        }
    }
    private var barrels: [Barrel] = []
    private var bombs: [Bomb] = []

    // Plane
    private var planeDir: CGFloat = 1
    private var planeX: CGFloat = -60
    private var planeY: CGFloat = 13

    // Timers (ms)
    private var elapsedMs: Double = 0
    private var lastBombDrop: Double = -100000
    private var lastBarrelSpawn: Double = -100000
    private var lastUpdateTime: TimeInterval = 0

    // Frame textures cache
    private var sheets: [String: [SKTexture]] = [:]
    private var explosionFrames: [SKTexture] = []
    private var currentSheetKey = "standingright"

    // Menu / HUD
    private var menuLayer: SKNode?
    private var controlsLayer: SKNode?
    private var controlForTouch: [AnyHashable: String] = [:]

    private let hitMessages = [
        "Code 3 loser!", "Level 3 OverG!!", "I dropped my pen find it!!",
        "Nice try, rookie!", "Better luck next time!", "Oops! That's gotta hurt!",
        "Mission failed!", "You got schooled!", "Back to training camp!",
        "Kaboom! Try again!", "Epic fail detected!", "Plot twist: You died!"
    ]

    // MARK: - Coordinate helper
    private func wc(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * S, y: y * S) }

    // MARK: - Lifecycle
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0x87 / 255, green: 0xce / 255, blue: 0xeb / 255, alpha: 1)
        scaleMode = .resizeFill
        addChild(worldNode)
        camera = cam
        addChild(cam)
        buildTextures()
        updateCameraZoom()
        showDifficultyMenu()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        updateCameraZoom()
        layoutControls()
    }

    /// Zoom the camera out (never in past 1x) so at least `minVisible*Units`
    /// of the world is visible in each axis. HUD/menu are camera children and
    /// are unaffected by camera scale, so they keep their on-screen sizes.
    private func updateCameraZoom() {
        guard size.width > 0, size.height > 0 else { return }
        let scaleW = minVisibleWidthUnits * S / size.width
        let scaleH = minVisibleHeightUnits * S / size.height
        let scale = min(max(1.0, max(scaleW, scaleH)), 3.0)
        cam.setScale(scale)
    }

    // MARK: - Texture building
    private func frames(_ imageName: String, cols: Int, rows: Int, topToBottom: Bool = true) -> [SKTexture] {
        let sheet = SKTexture(imageNamed: imageName)
        sheet.filteringMode = .nearest
        var result: [SKTexture] = []
        // Inset each frame slightly so we never sample a neighboring frame.
        let padX = (1 / CGFloat(cols)) * 0.03
        let padY = (1 / CGFloat(rows)) * 0.03
        for f in 0..<(cols * rows) {
            let col = f % cols
            let row = f / cols
            let yRow = topToBottom ? (rows - 1 - row) : row
            let rect = CGRect(x: CGFloat(col) / CGFloat(cols) + padX,
                              y: CGFloat(yRow) / CGFloat(rows) + padY,
                              width: 1 / CGFloat(cols) - 2 * padX,
                              height: 1 / CGFloat(rows) - 2 * padY)
            let t = SKTexture(rect: rect, in: sheet)
            t.filteringMode = .nearest
            result.append(t)
        }
        return result
    }

    private func buildTextures() {
        // Standing sheets are laid out 3 columns x 2 rows.
        for name in ["standingright", "standingleft"] {
            sheets[name] = frames(name, cols: 3, rows: 2)
        }
        // The remaining player sheets are laid out 2 columns x 3 rows.
        for name in ["runningright", "runningleft", "jumpingright", "jumpingleft",
                     "crouchingright", "crouchingleft", "victory"] {
            sheets[name] = frames(name, cols: 2, rows: 3)
        }
        explosionFrames = frames("explosionsprite", cols: 3, rows: 3)
    }

    // MARK: - Difficulty menu
    private func showDifficultyMenu() {
        started = false
        won = false
        worldNode.removeAllChildren()
        controlsLayer?.removeFromParent(); controlsLayer = nil
        cam.removeAllChildren()

        let layer = SKNode()
        layer.zPosition = 1000
        menuLayer = layer
        cam.addChild(layer)

        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.6), size: CGSize(width: 6000, height: 6000))
        dim.zPosition = 0
        layer.addChild(dim)

        let title = SKLabelNode(text: "JASON'S GAME")
        title.fontName = "AvenirNext-Heavy"
        title.fontSize = 44
        title.fontColor = .white
        title.position = CGPoint(x: 0, y: 120)
        title.zPosition = 1
        layer.addChild(title)

        let sub = SKLabelNode(text: "Select Difficulty")
        sub.fontName = "AvenirNext-Medium"
        sub.fontSize = 22
        sub.fontColor = SKColor(white: 0.85, alpha: 1)
        sub.position = CGPoint(x: 0, y: 70)
        sub.zPosition = 1
        layer.addChild(sub)

        let options: [(String, SKColor)] = [
            ("Easy", SKColor(red: 0.30, green: 0.75, blue: 0.35, alpha: 1)),
            ("Medium", SKColor(red: 0.95, green: 0.70, blue: 0.20, alpha: 1)),
            ("Hard", SKColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1))
        ]
        for (i, opt) in options.enumerated() {
            let btn = makeButton(text: opt.0, size: CGSize(width: 220, height: 54), color: opt.1)
            btn.name = "diff_\(opt.0)"
            btn.position = CGPoint(x: 0, y: 10 - CGFloat(i) * 70)
            btn.zPosition = 1
            layer.addChild(btn)
        }
    }

    private func makeButton(text: String, size: CGSize, color: SKColor) -> SKNode {
        let container = SKNode()
        let bg = SKShapeNode(rectOf: size, cornerRadius: 12)
        bg.fillColor = color
        bg.strokeColor = SKColor(white: 1, alpha: 0.5)
        bg.lineWidth = 2
        container.addChild(bg)
        let label = SKLabelNode(text: text)
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 24
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        container.addChild(label)
        return container
    }

    private func startGame() {
        menuLayer?.removeFromParent()
        menuLayer = nil
        worldNode.removeAllChildren()
        cam.removeAllChildren()
        barrels.removeAll(); bombs.removeAll()
        plane = nil; badGuy = nil
        started = true
        gamePaused = false
        won = false
        playerRespawning = false
        velX = 0; velY = 0; canJump = false
        moveLeft = false; moveRight = false; moveDown = false
        playerX = -35; playerY = 1
        planeDir = 1; planeX = -60; planeY = 13
        elapsedMs = 0; lastBombDrop = -100000; lastBarrelSpawn = -100000
        lastUpdateTime = 0

        buildLevel()
        setupControls()
    }

    // MARK: - Level construction
    private func buildLevel() {
        let backdrop = SKSpriteNode(imageNamed: "backdrop")
        backdrop.position = wc(0, 10)
        backdrop.size = CGSize(width: 200 * S, height: 100 * S)
        backdrop.zPosition = -10
        backdrop.alpha = 0.9
        worldNode.addChild(backdrop)

        grounds = [Ground(x: -35, w: 20), Ground(x: -5, w: 20), Ground(x: 25, w: 20), Ground(x: 55, w: 20)]
        for g in grounds {
            let node = SKShapeNode(rectOf: CGSize(width: g.w * S, height: 1 * S), cornerRadius: 4)
            node.fillColor = SKColor(red: 0x22 / 255, green: 0x8B / 255, blue: 0x22 / 255, alpha: 1)
            node.strokeColor = SKColor(red: 0x18 / 255, green: 0x60 / 255, blue: 0x18 / 255, alpha: 1)
            node.lineWidth = 3
            node.position = wc(g.x, -0.5)
            node.zPosition = 0
            worldNode.addChild(node)
            let grass = SKShapeNode(rectOf: CGSize(width: g.w * S, height: 0.18 * S))
            grass.fillColor = SKColor(red: 0x3c / 255, green: 0xb0 / 255, blue: 0x3c / 255, alpha: 1)
            grass.strokeColor = .clear
            grass.position = wc(g.x, -0.01)
            grass.zPosition = 0.1
            worldNode.addChild(grass)
        }

        platforms = []
        for i in 0..<10 {
            platforms.append(Platform(x: -40 + CGFloat(i) * 10, y: 2 + CGFloat(i % 2) * 2))
        }
        lastPlatformX = platforms.map { $0.x }.max() ?? 0
        for p in platforms {
            let node = SKShapeNode(rectOf: CGSize(width: 6 * S, height: 0.5 * S), cornerRadius: 6)
            node.fillColor = SKColor(red: 0x8B / 255, green: 0x45 / 255, blue: 0x13 / 255, alpha: 1)
            node.strokeColor = SKColor(red: 0x5c / 255, green: 0x2e / 255, blue: 0x0c / 255, alpha: 1)
            node.lineWidth = 2
            node.position = wc(p.x, p.y)
            node.zPosition = 1
            worldNode.addChild(node)
        }

        obstacles = []
        var i = 0
        while i < platforms.count {
            let p = platforms[i]
            obstacles.append(CGPoint(x: p.x, y: p.y + 1))
            i += 2
        }
        for o in obstacles {
            let node = SKShapeNode(rectOf: CGSize(width: 1 * S, height: 1 * S), cornerRadius: 3)
            node.fillColor = SKColor(white: 0.05, alpha: 1)
            node.strokeColor = SKColor(white: 0.3, alpha: 1)
            node.lineWidth = 2
            node.position = wc(o.x, o.y)
            node.zPosition = 2
            worldNode.addChild(node)
        }

        player = SKSpriteNode(texture: sheets["standingright"]?.first)
        player.size = CGSize(width: 1.8 * S, height: 2.4 * S)
        player.position = wc(playerX, playerY)
        player.zPosition = 5
        currentAnim = "idle"; animFrame = 0; animFrameTime = 0
        facingRight = true; lastDirectionRight = true
        worldNode.addChild(player)

        if let lastP = platforms.max(by: { $0.x < $1.x }) {
            let bg = SKSpriteNode(texture: sheets["standingleft"]?.first)
            bg.size = CGSize(width: 2 * S, height: 2 * S)
            bg.position = wc(lastP.x, lastP.y + 2)
            bg.zPosition = 4
            let bgFrames = frames("badguy", cols: 2, rows: 3)
            bg.run(SKAction.repeatForever(SKAction.animate(with: bgFrames, timePerFrame: 1.0 / 6.0)))
            worldNode.addChild(bg)
            badGuy = bg
        }

        let pl = SKSpriteNode(imageNamed: "f15")
        pl.size = CGSize(width: 6 * S, height: 2 * S)
        pl.position = wc(planeX, planeY)
        pl.zPosition = 6
        worldNode.addChild(pl)
        plane = pl

        cam.position = wc(playerX, playerY + camOffsetY)
    }

    // MARK: - Update loop
    override func update(_ currentTime: TimeInterval) {
        guard started, !gamePaused else { lastUpdateTime = currentTime; return }
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let dt = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        elapsedMs += dt * 1000

        if won { updateVictoryAnimation(); return }

        movePlaneAndDropBombs()
        moveBombs()

        if !playerRespawning {
            if moveLeft { velX = -moveSpeed }
            else if moveRight { velX = moveSpeed }
            else { velX = 0 }
        } else {
            velX = 0
        }

        var mustStayCrouched = false
        if moveDown && canJump && abs(velY) < 0.001 {
            for plat in platforms {
                let playerStandingTop = playerY + 1.2
                let platBottom = plat.y - 0.25
                if abs(playerX - plat.x) < 3 && playerStandingTop > platBottom && playerY < platBottom {
                    mustStayCrouched = true
                    break
                }
            }
        }

        if playerX >= lastPlatformX + 4 {
            velX = 0; velY = 0
            triggerVictory()
            return
        }

        updatePlayerAnimation(mustStayCrouched: mustStayCrouched)

        velY += gravity

        var nextY = playerY + velY
        var onPlatform = false
        for plat in platforms {
            let prevY = playerY
            let platTop = plat.y + 0.5
            if abs(playerX - plat.x) < 3.5 && abs(nextY - platTop) < 1.01 && velY <= 0 && prevY >= platTop {
                nextY = platTop + 1.0
                velY = 0; canJump = true; onPlatform = true
                break
            }
            let playerHeadY = nextY + 1.2
            if abs(playerX - plat.x) < 3.5 && velY > 0 &&
                playerHeadY > plat.y - 0.25 && playerY + 1.2 <= plat.y - 0.25 {
                nextY = plat.y - 0.25 - 1.2
                velY = 0
            }
        }

        var onGround = false
        for g in grounds {
            if playerX > g.x - g.w / 2 && playerX < g.x + g.w / 2 && nextY <= 1 && velY <= 0 {
                nextY = 1; velY = 0; canJump = true; onGround = true
                break
            }
        }
        if !onPlatform && !onGround { canJump = false }

        var nextX = playerX + velX
        var blocked = false
        let crouching = (moveDown || mustStayCrouched) && canJump && abs(velY) < 0.001
        for plat in platforms {
            let playerHeight: CGFloat = crouching ? 0.7 : 1.2
            let playerBottom = playerY
            let playerTop = playerY + playerHeight
            let platBottom = plat.y - 0.25
            let platTop = plat.y + 0.25
            if playerTop > platBottom && playerBottom < platTop {
                let platLeft = plat.x - 3
                let platRight = plat.x + 3
                if nextX + 0.5 > platLeft && nextX - 0.5 < platRight {
                    if crouching && playerTop <= platBottom + 0.1 && playerY <= platBottom {
                        continue
                    } else {
                        blocked = true
                        break
                    }
                }
            }
        }
        for o in obstacles {
            if abs(nextX - o.x) < 1 && abs(playerY - o.y) < 2 {
                blocked = true
                break
            }
        }
        if !blocked { playerX = nextX }

        if crouching {
            playerY = nextY - 0.5
        } else {
            playerY = nextY
        }

        if playerY < -10 || playerX < -70 || playerX > 70 {
            resetPlayerToStart()
        }

        cam.position = wc(playerX, playerY + camOffsetY)
        player.position = wc(playerX, playerY)

        spawnBarrels()
        moveBarrels()
    }

    // MARK: - Plane & bombs
    private func movePlaneAndDropBombs() {
        guard let plane, !playerRespawning else { return }
        planeX += 0.25 * planeDir
        plane.xScale = planeDir
        if planeX > 60 { planeDir = -1 }
        if planeX < -60 { planeDir = 1 }
        plane.position = wc(planeX, planeY)

        if CGFloat.random(in: 0...1) < 0.01 && elapsedMs - lastBombDrop > 800 {
            let numBombs = Bool.random() ? 1 : Int.random(in: 2...3)
            for _ in 0..<numBombs {
                let node = SKSpriteNode(imageNamed: "gbu12")
                node.size = CGSize(width: 0.7 * S, height: 2 * S)
                node.zPosition = 3
                let b = Bomb(node: node, x: planeX, y: planeY - 1, vx: 0, vy: CGFloat.random(in: -0.12 ... -0.05))
                node.position = wc(b.x, b.y)
                worldNode.addChild(node)
                bombs.append(b)
            }
            lastBombDrop = elapsedMs
        }
    }

    private func moveBombs() {
        guard !playerRespawning else { return }
        for i in stride(from: bombs.count - 1, through: 0, by: -1) {
            let bomb = bombs[i]
            if bomb.hit { continue }
            bomb.vy += gravity * 0.18 - 0.04
            bomb.x += bomb.vx
            bomb.y += bomb.vy
            if bomb.y < 0 {
                bomb.node.removeFromParent()
                bombs.remove(at: i)
                continue
            }
            bomb.node.position = wc(bomb.x, bomb.y)
            if abs(playerX - bomb.x) < 1 && abs(playerY - bomb.y) < 1.5 {
                bomb.hit = true
                createExplosion(x: bomb.x, y: bomb.y)
                showHitMessage(x: bomb.x, y: bomb.y)
                bomb.node.removeFromParent()
                bombs.remove(at: i)
                resetPlayerWithDelay()
            }
        }
    }

    // MARK: - Barrels
    private func badGuyX() -> CGFloat { badGuy.map { $0.position.x / S } ?? 50 }
    private func badGuyY(defaultY: CGFloat) -> CGFloat { badGuy.map { $0.position.y / S } ?? defaultY }

    private func spawnBarrels() {
        guard badGuy != nil, barrels.count < 3, !playerRespawning,
              elapsedMs - lastBarrelSpawn > barrelSpawnIntervalMs else { return }
        let node = SKShapeNode(circleOfRadius: 0.7 * S)
        node.fillColor = SKColor(red: 0x8B / 255, green: 0x8B / 255, blue: 0x7A / 255, alpha: 1)
        node.strokeColor = SKColor(white: 0.2, alpha: 1)
        node.lineWidth = 3
        let stripe = SKShapeNode(rectOf: CGSize(width: 0.2 * S, height: 1.4 * S))
        stripe.fillColor = SKColor(white: 0.35, alpha: 1)
        stripe.strokeColor = .clear
        node.addChild(stripe)
        node.zPosition = 3

        let isBouncing = barrels.count % 2 == 0
        let x = badGuyX()
        let y = isBouncing ? badGuyY(defaultY: 6) : 1
        let vx = -barrelMinSpeed - CGFloat.random(in: 0...(barrelMaxSpeed - barrelMinSpeed))
        let barrel = Barrel(node: node, x: x, y: y, vx: vx, vy: 0, bouncing: isBouncing)
        node.position = wc(x, y)
        worldNode.addChild(node)
        barrels.append(barrel)
        lastBarrelSpawn = elapsedMs
    }

    private func moveBarrels() {
        guard !playerRespawning else { return }
        for barrel in barrels {
            if barrel.bouncing {
                barrel.vy += gravity
                var nextY = barrel.y + barrel.vy
                var bounced = false
                for plat in platforms {
                    if abs(barrel.x - plat.x) < 3.5 &&
                        barrel.y >= plat.y + 0.5 &&
                        nextY <= plat.y + 1.2 {
                        nextY = plat.y + 1.2
                        barrel.vy = 0.4 + CGFloat.random(in: 0...0.2)
                        bounced = true
                        break
                    }
                }
                if !bounced && nextY <= 1 {
                    nextY = 1
                    barrel.vy = 0.4 + CGFloat.random(in: 0...0.2)
                }
                barrel.x += barrel.vx
                barrel.y = nextY
            } else {
                barrel.x += barrel.vx
                barrel.y = 1
            }
            barrel.node.zRotation += abs(barrel.vx) * 0.15
            if barrel.x < -55 {
                let isBouncing = Bool.random()
                barrel.x = badGuyX()
                barrel.y = isBouncing ? badGuyY(defaultY: 2 + CGFloat.random(in: 0...2)) : 1
                barrel.vy = 0
                barrel.bouncing = isBouncing
                barrel.node.zRotation = 0
            }
            barrel.node.position = wc(barrel.x, barrel.y)

            if abs(playerX - barrel.x) < 1.2 && abs(playerY - barrel.y) < 1.5 {
                createExplosion(x: barrel.x, y: barrel.y)
                showHitMessage(x: barrel.x, y: barrel.y)
                resetPlayerWithDelay()
            }
        }
    }

    // MARK: - Player animation
    private func switchSprite(_ anim: String, facingRight: Bool) {
        switch anim {
        case "idle", "standing": currentSheetKey = facingRight ? "standingright" : "standingleft"
        case "run": currentSheetKey = facingRight ? "runningright" : "runningleft"
        case "jump": currentSheetKey = facingRight ? "jumpingright" : "jumpingleft"
        case "crouch": currentSheetKey = facingRight ? "crouchingright" : "crouchingleft"
        case "victory": currentSheetKey = "victory"
        default: break
        }
    }

    private func updatePlayerAnimation(mustStayCrouched: Bool) {
        guard player != nil else { return }
        if velX > 0 { facingRight = true; lastDirectionRight = true }
        else if velX < 0 { facingRight = false; lastDirectionRight = false }
        else { facingRight = lastDirectionRight }

        var newAnim = "idle"
        if (moveDown || mustStayCrouched) && canJump && abs(velY) < 0.001 { newAnim = "crouch" }
        else if abs(velY) > 0.01 { newAnim = "jump" }
        else if abs(velX) > 0.01 { newAnim = "run" }
        else { newAnim = "idle" }

        if newAnim != currentAnim {
            currentAnim = newAnim
            animFrame = 0
            animFrameTime = 0
        }
        switchSprite(newAnim, facingRight: facingRight)

        animFrameTime += 1
        if animFrameTime >= 60 / animFrameRate {
            animFrameTime = 0
            let frameCount = (newAnim == "jump" || newAnim == "crouch") ? 3 : 6
            animFrame = (animFrame + 1) % frameCount
        }
        if let f = sheets[currentSheetKey], animFrame < f.count {
            player.texture = f[animFrame]
        }
    }

    private func triggerVictory() {
        guard !won else { return }
        won = true
        currentAnim = "victory"; animFrame = 0; animFrameTime = 0
        currentSheetKey = "victory"
        player.position = wc(playerX, playerY)

        let label = SKLabelNode(text: "YOU WIN! 🎉")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 40
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: 100)
        label.zPosition = 1000
        label.name = "winLabel"
        cam.addChild(label)

        let tapHint = SKLabelNode(text: "Tap to play again")
        tapHint.fontName = "AvenirNext-Medium"
        tapHint.fontSize = 22
        tapHint.fontColor = SKColor(white: 0.9, alpha: 1)
        tapHint.position = CGPoint(x: 0, y: 55)
        tapHint.zPosition = 1000
        tapHint.name = "winLabel"
        cam.addChild(tapHint)
    }

    private func updateVictoryAnimation() {
        animFrameTime += 1
        if animFrameTime >= 60 / animFrameRate {
            animFrameTime = 0
            animFrame = (animFrame + 1) % 6
        }
        if let f = sheets["victory"], animFrame < f.count { player.texture = f[animFrame] }
    }

    // MARK: - Reset / respawn
    private func resetPlayerToStart() {
        playerX = -35; playerY = 1
        velX = 0; velY = 0
        canJump = true
        moveLeft = false; moveRight = false; moveDown = false
        playerRespawning = false
        for b in barrels { b.node.removeFromParent() }
        barrels.removeAll()
        lastBarrelSpawn = elapsedMs
        for b in bombs { b.node.removeFromParent() }
        bombs.removeAll()
        lastBombDrop = elapsedMs
        player.position = wc(playerX, playerY)
        cam.position = wc(playerX, playerY + camOffsetY)
    }

    private func resetPlayerWithDelay() {
        guard !playerRespawning else { return }
        playerRespawning = true
        velX = 0; velY = 0
        moveLeft = false; moveRight = false; moveDown = false
        run(SKAction.sequence([.wait(forDuration: 1.0), .run { [weak self] in self?.resetPlayerToStart() }]))
    }

    // MARK: - Effects
    private func createExplosion(x: CGFloat, y: CGFloat) {
        guard !explosionFrames.isEmpty else { return }
        makeSingleExplosion(x: x, y: y, sizeMultiplier: 1.0)
        for _ in 0..<3 {
            let ox = CGFloat.random(in: -1...1)
            let oy = CGFloat.random(in: -1...1)
            let delay = Double.random(in: 0...0.33)
            let scale = 0.5 + CGFloat.random(in: 0...0.5)
            run(SKAction.sequence([.wait(forDuration: delay),
                                   .run { [weak self] in self?.makeSingleExplosion(x: x + ox, y: y + oy, sizeMultiplier: scale) }]))
        }
    }

    private func makeSingleExplosion(x: CGFloat, y: CGFloat, sizeMultiplier: CGFloat) {
        let node = SKSpriteNode(texture: explosionFrames.first)
        node.size = CGSize(width: 3 * S * sizeMultiplier, height: 3 * S * sizeMultiplier)
        node.position = wc(x, y)
        node.zPosition = 20
        node.zRotation = CGFloat.random(in: 0...(2 * .pi))
        node.setScale(0.2)
        node.blendMode = .add
        worldNode.addChild(node)
        let duration: TimeInterval = 9.0 / 12.0
        let anim = SKAction.animate(with: explosionFrames, timePerFrame: duration / 9.0)
        let grow = SKAction.scale(to: 1.0, duration: duration)
        let fade = SKAction.sequence([.wait(forDuration: duration * 0.6), .fadeOut(withDuration: duration * 0.4)])
        node.run(SKAction.group([anim, grow, fade])) { node.removeFromParent() }
    }

    private func showHitMessage(x: CGFloat, y: CGFloat) {
        let msg = hitMessages.randomElement() ?? "Ouch!"
        let label = SKLabelNode(text: msg)
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 26
        label.fontColor = SKColor(red: 1, green: 0.27, blue: 0.27, alpha: 1)
        label.position = wc(x, y + 3)
        label.zPosition = 30
        label.setScale(0.5)
        worldNode.addChild(label)
        let pop = SKAction.scale(to: 1.2, duration: 0.15)
        let settle = SKAction.scale(to: 1.0, duration: 0.15)
        let rise = SKAction.moveBy(x: 0, y: 0.8 * S, duration: 2.0)
        let fade = SKAction.sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 1.5)])
        label.run(SKAction.group([SKAction.sequence([pop, settle]), rise, fade])) { label.removeFromParent() }
    }

    // MARK: - On-screen controls
    private func setupControls() {
        controlsLayer?.removeFromParent()
        let layer = SKNode()
        layer.zPosition = 500
        cam.addChild(layer)
        controlsLayer = layer

        for (name, symbol) in [("btnLeft", "◀"), ("btnRight", "▶"), ("btnCrouch", "▼"), ("btnJump", "▲")] {
            let btn = SKShapeNode(circleOfRadius: 42)
            btn.fillColor = SKColor(white: 1, alpha: 0.18)
            btn.strokeColor = SKColor(white: 1, alpha: 0.5)
            btn.lineWidth = 2
            btn.name = name
            let label = SKLabelNode(text: symbol)
            label.fontName = "AvenirNext-Bold"
            label.fontSize = 34
            label.fontColor = SKColor(white: 1, alpha: 0.85)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            btn.addChild(label)
            layer.addChild(btn)
        }
        layoutControls()
    }

    private func layoutControls() {
        guard let layer = controlsLayer else { return }
        let halfW = size.width / 2
        let halfH = size.height / 2
        let margin: CGFloat = 60
        let gap: CGFloat = 100
        layer.childNode(withName: "btnLeft")?.position = CGPoint(x: -halfW + margin, y: -halfH + margin)
        layer.childNode(withName: "btnRight")?.position = CGPoint(x: -halfW + margin + gap, y: -halfH + margin)
        layer.childNode(withName: "btnCrouch")?.position = CGPoint(x: halfW - margin - gap, y: -halfH + margin)
        layer.childNode(withName: "btnJump")?.position = CGPoint(x: halfW - margin, y: -halfH + margin)
    }

    // MARK: - Input handling (shared)
    private func doJump() {
        if canJump && !won && !playerRespawning {
            velY = jumpStrength
            canJump = false
        }
    }

    private func release(_ control: String) {
        switch control {
        case "btnLeft": moveLeft = false
        case "btnRight": moveRight = false
        case "btnCrouch": moveDown = false
        default: break
        }
    }

    /// Handle a press at a scene location.
    @discardableResult
    fileprivate func handlePress(at location: CGPoint, id: AnyHashable?) -> Bool {
        let tapped = nodes(at: location)

        if !started {
            for n in tapped {
                var node: SKNode? = n
                while let cur = node {
                    if let name = cur.name, name.hasPrefix("diff_") {
                        switch name {
                        case "diff_Easy": applyDifficulty(.easy)
                        case "diff_Hard": applyDifficulty(.hard)
                        default: applyDifficulty(.medium)
                        }
                        startGame()
                        return true
                    }
                    node = cur.parent
                }
            }
            return true
        }

        if won {
            showDifficultyMenu()
            return true
        }

        for n in tapped {
            var node: SKNode? = n
            while let cur = node {
                switch cur.name {
                case "btnLeft": moveLeft = true; if let id { controlForTouch[id] = "btnLeft" }; return true
                case "btnRight": moveRight = true; if let id { controlForTouch[id] = "btnRight" }; return true
                case "btnCrouch": moveDown = true; if let id { controlForTouch[id] = "btnCrouch" }; return true
                case "btnJump": doJump(); if let id { controlForTouch[id] = "btnJump" }; return true
                default: break
                }
                node = cur.parent
            }
        }
        return false
    }

    fileprivate func releaseTouch(_ id: AnyHashable) {
        if let control = controlForTouch[id] { release(control); controlForTouch[id] = nil }
    }

    fileprivate func releaseAllPointerButtons() {
        moveLeft = false; moveRight = false; moveDown = false
        controlForTouch.removeAll()
    }
}

// MARK: - Touch input (iOS / tvOS / visionOS)
#if os(iOS) || os(tvOS) || os(visionOS)
extension GameScene {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            handlePress(at: t.location(in: self), id: ObjectIdentifier(t))
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { releaseTouch(ObjectIdentifier(t)) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}
#endif

// MARK: - Keyboard & mouse input (macOS)
#if os(macOS)
extension GameScene {
    override func mouseDown(with event: NSEvent) {
        handlePress(at: event.location(in: self), id: nil)
    }
    override func mouseUp(with event: NSEvent) {
        releaseAllPointerButtons()
    }
    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }
        switch event.keyCode {
        case 123, 0: moveLeft = true
        case 124, 2: moveRight = true
        case 125, 1: moveDown = true
        case 126, 13, 49: doJump()
        case 15: resetPlayerToStart()
        default: break
        }
    }
    override func keyUp(with event: NSEvent) {
        switch event.keyCode {
        case 123, 0: moveLeft = false
        case 124, 2: moveRight = false
        case 125, 1: moveDown = false
        default: break
        }
    }
}
#endif
