package com.jasonstoops.plaingame

import android.content.Context
import android.graphics.*
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import java.util.*
import kotlin.math.*

class GameView(context: Context) : SurfaceView(context), SurfaceHolder.Callback, Runnable {

    private var gameThread: Thread? = null
    private var running = false
    private val holder: SurfaceHolder = getHolder().apply { addCallback(this@GameView) }

    // MARK: - World scale
    private var S: Float = 40f 

    // MARK: - Difficulty
    enum class Difficulty { EASY, MEDIUM, HARD }
    private var difficulty: Difficulty = Difficulty.MEDIUM
    private var moveSpeed: Float = 0.2f
    private var barrelMinSpeed: Float = 0.15f
    private var barrelMaxSpeed: Float = 0.25f
    private var barrelSpawnIntervalMs: Double = 120.0 * 8

    private fun applyDifficulty(level: Difficulty) {
        difficulty = level
        when (level) {
            Difficulty.EASY -> {
                moveSpeed = 0.15f; barrelMinSpeed = 0.10f; barrelMaxSpeed = 0.18f; barrelSpawnIntervalMs = 180.0 * 8
            }
            Difficulty.MEDIUM -> {
                moveSpeed = 0.2f; barrelMinSpeed = 0.15f; barrelMaxSpeed = 0.25f; barrelSpawnIntervalMs = 120.0 * 8
            }
            Difficulty.HARD -> {
                moveSpeed = 0.28f; barrelMinSpeed = 0.22f; barrelMaxSpeed = 0.32f; barrelSpawnIntervalMs = 70.0 * 8
            }
        }
    }

    // MARK: - Physics constants (world units)
    private val jumpStrength: Float = 0.5f
    private val gravity: Float = -0.02f
    private val camOffsetY: Float = 3f
    private val minVisibleWidthUnits: Float = 12f
    private val minVisibleHeightUnits: Float = 16f

    // MARK: - Player state
    private var playerX: Float = -35f
    private var playerY: Float = 1f
    private var velX: Float = 0f
    private var velY: Float = 0f
    private var canJump = false
    private var facingRight = true
    private var lastDirectionRight = true

    // Input flags: keyboard and touch are tracked separately and OR'd together,
    // so a touch event (e.g. clicking the window for focus) can't stomp held keyboard keys.
    private var keyMoveLeft = false
    private var keyMoveRight = false
    private var keyMoveDown = false
    private var touchMoveLeft = false
    private var touchMoveRight = false
    private var touchMoveDown = false
    private val moveLeft get() = keyMoveLeft || touchMoveLeft
    private val moveRight get() = keyMoveRight || touchMoveRight
    private val moveDown get() = keyMoveDown || touchMoveDown

    // Animation
    private var currentAnim = "idle"
    private var animFrame = 0
    private var animFrameTime = 0
    private val animFrameRate = 10

    // MARK: - Game flow
    private var started = false
    private var gamePaused = false
    private var playerRespawning = false
    private var won = false

    // MARK: - Geometry
    data class Ground(val x: Float, val w: Float)
    data class Platform(val x: Float, val y: Float)
    private val grounds = mutableListOf<Ground>()
    private val platforms = mutableListOf<Platform>()
    private val obstacles = mutableListOf<PointF>()
    private var lastPlatformX: Float = 0f
    private var badGuyX: Float = 50f
    private var badGuyY: Float = 4f

    // MARK: - Dynamic objects
    class Barrel(var x: Float, var y: Float, var vx: Float, var vy: Float, var bouncing: Boolean) {
        var rotation: Float = 0f
    }
    class Bomb(var x: Float, var y: Float, var vx: Float, var vy: Float) {
        var hit = false
    }
    private val barrels = mutableListOf<Barrel>()
    private val bombs = mutableListOf<Bomb>()

    // Explosions
    class Explosion(val x: Float, val y: Float) {
        var frame = 0
        var frameTime = 0
    }
    private val explosions = mutableListOf<Explosion>()

    // Plane
    private var planeDir: Float = 1f
    private var planeX: Float = -60f
    private var planeY: Float = 13f

    // Timers
    private var elapsedMs: Double = 0.0
    private var lastBombDrop: Double = -100000.0
    private var lastBarrelSpawn: Double = -100000.0
    private var lastUpdateTime: Long = 0

    // Camera
    private var camX: Float = 0f
    private var camY: Float = 0f
    private var camScale: Float = 1f

    private val random = Random()

    // Paint objects
    private val bgPaint = Paint().apply { color = Color.parseColor("#87CEEB"); isAntiAlias = true }
    private val groundPaint = Paint().apply { color = Color.parseColor("#228B22"); isAntiAlias = true }
    private val grassPaint = Paint().apply { color = Color.parseColor("#3CB03C"); isAntiAlias = true }
    private val platformPaint = Paint().apply { color = Color.parseColor("#8B4513"); isAntiAlias = true }
    private val obstaclePaint = Paint().apply { color = Color.parseColor("#0D0D0D"); isAntiAlias = true }
    private val textPaint = Paint().apply {
        color = Color.WHITE
        textSize = 100f
        textAlign = Paint.Align.CENTER
        typeface = Typeface.DEFAULT_BOLD
        isAntiAlias = true
        setShadowLayer(10f, 2f, 2f, Color.BLACK)
    }
    private val bitmapPaint = Paint().apply { isFilterBitmap = true; isAntiAlias = true }
    
    // UI Paints
    private val uiButtonPaint = Paint().apply {
        color = Color.WHITE
        alpha = 80
        style = Paint.Style.FILL
        isAntiAlias = true
    }
    private val uiButtonStrokePaint = Paint().apply {
        color = Color.WHITE
        alpha = 150
        style = Paint.Style.STROKE
        strokeWidth = 5f
        isAntiAlias = true
    }
    private val uiTextPaint = Paint().apply {
        color = Color.WHITE
        alpha = 200
        textSize = 40f
        textAlign = Paint.Align.CENTER
        typeface = Typeface.DEFAULT_BOLD
        isAntiAlias = true
    }

    // UI Buttons
    private var btnLeft = RectF()
    private var btnRight = RectF()
    private var btnJump = RectF()
    private var btnCrouch = RectF()

    // Sprite Sheets
    class SpriteSheet(val bitmap: Bitmap, val cols: Int, val rows: Int)
    private var playerSheets = mutableMapOf<String, SpriteSheet>()
    private var explosionSheet: SpriteSheet? = null
    
    private var planeBitmap: Bitmap? = null
    private var bombBitmap: Bitmap? = null
    private var backdropBitmap: Bitmap? = null

    // Bad guy: the stationary barrel-thrower NPC that stands on the last platform
    private var badGuyFrame = 0
    private var badGuyFrameTime = 0
    private val badGuyFrameRate = 6

    // Barrel look (matches the original: a rolling drum, not a character sprite)
    private val barrelBodyPaint = Paint().apply { color = Color.parseColor("#8B8B7A"); isAntiAlias = true }
    private val barrelStrokePaint = Paint().apply {
        color = Color.parseColor("#333333"); style = Paint.Style.STROKE; strokeWidth = 3f; isAntiAlias = true
    }
    private val barrelStripePaint = Paint().apply { color = Color.parseColor("#595959"); isAntiAlias = true }

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        applyDifficulty(Difficulty.MEDIUM)
        loadBitmaps()
    }

    private fun loadBitmaps() {
        planeBitmap = loadBitmap("f15")
        bombBitmap = loadBitmap("gbu12")
        backdropBitmap = loadBitmap("backdrop")

        fun loadSheet(name: String, cols: Int, rows: Int) {
            val bmp = loadBitmap(name)
            if (bmp != null) playerSheets[name] = SpriteSheet(bmp, cols, rows)
        }

        loadSheet("standingright", 3, 2)
        loadSheet("standingleft", 3, 2)
        loadSheet("runningright", 2, 3)
        loadSheet("runningleft", 2, 3)
        loadSheet("jumpingright", 2, 3)
        loadSheet("jumpingleft", 2, 3)
        loadSheet("crouchingright", 2, 3)
        loadSheet("crouchingleft", 2, 3)
        loadSheet("victory", 2, 3)
        loadSheet("badguy", 2, 3)

        val expBmp = loadBitmap("explosionsprite")
        if (expBmp != null) explosionSheet = SpriteSheet(expBmp, 3, 3)
    }

    private fun loadBitmap(name: String): Bitmap? {
        val id = context.resources.getIdentifier(name, "drawable", context.packageName)
        return if (id != 0) BitmapFactory.decodeResource(context.resources, id) else null
    }

    private fun drawBitmapFrame(canvas: Canvas, sheet: SpriteSheet, frame: Int, dst: RectF, alpha: Int = 255) {
        val w = sheet.bitmap.width / sheet.cols
        val h = sheet.bitmap.height / sheet.rows
        val col = frame % sheet.cols
        val row = frame / sheet.cols
        val src = Rect(col * w, row * h, (col + 1) * w, (row + 1) * h)
        bitmapPaint.alpha = alpha
        canvas.drawBitmap(sheet.bitmap, src, dst, bitmapPaint)
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        start()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        updateCameraZoom(width.toFloat(), height.toFloat())
        layoutButtons(width.toFloat(), height.toFloat())
    }

    private fun layoutButtons(w: Float, h: Float) {
        val btnSize = 160f
        val margin = 60f
        val gap = 40f
        
        btnLeft = RectF(margin, h - margin - btnSize, margin + btnSize, h - margin)
        btnRight = RectF(margin + btnSize + gap, h - margin - btnSize, margin + 2 * btnSize + gap, h - margin)
        
        btnJump = RectF(w - margin - btnSize, h - margin - btnSize, w - margin, h - margin)
        btnCrouch = RectF(w - margin - 2 * btnSize - gap, h - margin - btnSize, w - margin - btnSize - gap, h - margin)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        stop()
    }

    private fun start() {
        if (running) return
        running = true
        gameThread = Thread(this)
        gameThread?.start()
    }

    private fun stop() {
        running = false
        try {
            gameThread?.join()
        } catch (e: InterruptedException) {
            e.printStackTrace()
        }
    }

    private fun updateCameraZoom(width: Float, height: Float) {
        val scaleW = minVisibleWidthUnits * S / width
        val scaleH = minVisibleHeightUnits * S / height
        camScale = 1f / max(1.0f, max(scaleW, scaleH)).coerceAtMost(3.0f)
    }

    override fun run() {
        while (running) {
            val currentTime = System.currentTimeMillis()
            if (lastUpdateTime == 0L) lastUpdateTime = currentTime
            val dt = (currentTime - lastUpdateTime).toDouble()
            lastUpdateTime = currentTime

            update(dt)
            draw()

            val sleepTime = 16 - (System.currentTimeMillis() - currentTime)
            if (sleepTime > 0) {
                try {
                    Thread.sleep(sleepTime)
                } catch (e: InterruptedException) {}
            }
        }
    }

    private fun startGame() {
        barrels.clear()
        bombs.clear()
        explosions.clear()
        started = true
        gamePaused = false
        won = false
        playerRespawning = false
        velX = 0f; velY = 0f; canJump = false
        keyMoveLeft = false; keyMoveRight = false; keyMoveDown = false; touchMoveLeft = false; touchMoveRight = false; touchMoveDown = false
        playerX = -35f; playerY = 1f
        planeDir = 1f; planeX = -60f; planeY = 13f
        elapsedMs = 0.0; lastBombDrop = -100000.0; lastBarrelSpawn = -100000.0
        buildLevel()
    }

    private fun buildLevel() {
        grounds.clear()
        grounds.add(Ground(-35f, 20f))
        grounds.add(Ground(-5f, 20f))
        grounds.add(Ground(25f, 20f))
        grounds.add(Ground(55f, 20f))

        platforms.clear()
        for (i in 0 until 10) {
            platforms.add(Platform(-40f + i * 10f, 2f + (i % 2) * 2f))
        }
        val lastPlatform = platforms.maxByOrNull { it.x }
        lastPlatformX = lastPlatform?.x ?: 0f
        badGuyX = lastPlatformX
        badGuyY = lastPlatform?.y ?: 2f

        obstacles.clear()
        for (i in 0 until platforms.size step 2) {
            val p = platforms[i]
            obstacles.add(PointF(p.x, p.y))
        }
    }

    private fun update(dtMs: Double) {
        if (!started || gamePaused) return
        elapsedMs += dtMs

        if (won) {
            updateVictoryAnimation()
            return
        }

        updateExplosions()
        updateBadGuyAnimation()
        movePlaneAndDropBombs(dtMs)
        moveBombs(dtMs)

        if (!playerRespawning) {
            if (moveLeft) velX = -moveSpeed
            else if (moveRight) velX = moveSpeed
            else velX = 0f
        } else {
            velX = 0f
        }

        var mustStayCrouched = false
        if (moveDown && canJump && abs(velY) < 0.001f) {
            for (plat in platforms) {
                val platTop = plat.y
                if (abs(playerX - plat.x) < 3 && playerY >= platTop && playerY < platTop + 0.5f) {
                    mustStayCrouched = true
                    break
                }
            }
        }

        if (playerX >= lastPlatformX + 4) {
            triggerVictory()
            return
        }

        updatePlayerAnimation(mustStayCrouched)

        velY += gravity

        var nextY = playerY + velY
        var onPlatform = false
        for (plat in platforms) {
            val prevY = playerY
            val platTop = plat.y 
            if (abs(playerX - plat.x) < 3.5f && abs(nextY - platTop) < 0.5f && velY <= 0 && prevY >= platTop) {
                nextY = platTop
                velY = 0f; canJump = true; onPlatform = true
                break
            }
            val playerHeadY = nextY + 2.4f
            val platBottom = plat.y - 0.5f
            if (abs(playerX - plat.x) < 3.5f && velY > 0 &&
                playerHeadY > platBottom && playerY + 2.4f <= platBottom) {
                nextY = platBottom - 2.4f
                velY = 0f
            }
        }

        var onGround = false
        for (g in grounds) {
            if (playerX > g.x - g.w / 2 && playerX < g.x + g.w / 2 && nextY <= 1 && velY <= 0) {
                nextY = 1f; velY = 0f; canJump = true; onGround = true
                break
            }
        }
        if (!onPlatform && !onGround) canJump = false

        var nextX = playerX + velX
        var blocked = false
        val crouching = (moveDown || mustStayCrouched) && canJump && abs(velY) < 0.001f
        for (plat in platforms) {
            val playerHeight = if (crouching) 1.2f else 2.4f
            val playerBottom = nextY
            val playerTop = nextY + playerHeight
            val platBottom = plat.y - 0.5f
            val platTop = plat.y
            if (playerTop > platBottom && playerBottom < platTop) {
                val platLeft = plat.x - 3
                val platRight = plat.x + 3
                if (nextX + 0.5f > platLeft && nextX - 0.5f < platRight) {
                    blocked = true
                    break
                }
            }
        }
        for (o in obstacles) {
            if (abs(nextX - o.x) < 1 && abs(playerY - o.y) < 1) {
                blocked = true
                break
            }
        }
        if (!blocked) playerX = nextX

        playerY = nextY

        if (playerY < -10 || playerX < -70 || playerX > 70) {
            resetPlayerToStart()
        }

        // Smooth camera follow
        val lerpFactor = 0.1f
        camX += (playerX - camX) * lerpFactor
        camY += (playerY + camOffsetY - camY) * lerpFactor

        spawnBarrels()
        moveBarrels(dtMs)
    }

    private fun updateExplosions() {
        val iterator = explosions.iterator()
        while (iterator.hasNext()) {
            val e = iterator.next()
            e.frameTime++
            if (e.frameTime >= 4) {
                e.frameTime = 0
                e.frame++
                if (explosionSheet != null && e.frame >= explosionSheet!!.cols * explosionSheet!!.rows) {
                    iterator.remove()
                }
            }
        }
    }

    private fun updateBadGuyAnimation() {
        val sheet = playerSheets["badguy"] ?: return
        badGuyFrameTime++
        if (badGuyFrameTime >= 60 / badGuyFrameRate) {
            badGuyFrameTime = 0
            badGuyFrame = (badGuyFrame + 1) % (sheet.cols * sheet.rows)
        }
    }

    private fun movePlaneAndDropBombs(dtMs: Double) {
        if (playerRespawning) return
        planeX += 0.25f * planeDir
        if (planeX > 60) planeDir = -1f
        if (planeX < -60) planeDir = 1f

        if (random.nextFloat() < 0.01f && elapsedMs - lastBombDrop > 800) {
            val numBombs = if (random.nextBoolean()) 1 else random.nextInt(2) + 1
            for (i in 0 until numBombs) {
                bombs.add(Bomb(planeX + (random.nextFloat() - 0.5f) * 2f, planeY - 1f, 0f, -0.05f - random.nextFloat() * 0.07f))
            }
            lastBombDrop = elapsedMs
        }
    }

    private fun moveBombs(dtMs: Double) {
        if (playerRespawning) return
        val iterator = bombs.iterator()
        while (iterator.hasNext()) {
            val bomb = iterator.next()
            if (bomb.hit) continue
            bomb.vy += gravity * 0.18f - 0.04f
            bomb.x += bomb.vx
            bomb.y += bomb.vy
            if (bomb.y < 0) {
                explosions.add(Explosion(bomb.x, 0.5f))
                iterator.remove()
                continue
            }
            if (abs(playerX - bomb.x) < 1 && abs(playerY - bomb.y) < 1.5) {
                bomb.hit = true
                explosions.add(Explosion(bomb.x, bomb.y))
                resetPlayerWithDelay()
                iterator.remove()
            }
        }
    }

    private fun spawnBarrels() {
        if (barrels.size >= 3 || playerRespawning || elapsedMs - lastBarrelSpawn < barrelSpawnIntervalMs) return
        val isBouncing = barrels.size % 2 == 0
        val x = badGuyX
        val y = if (isBouncing) badGuyY else 1f
        val vx = -barrelMinSpeed - random.nextFloat() * (barrelMaxSpeed - barrelMinSpeed)
        barrels.add(Barrel(x, y, vx, 0f, isBouncing))
        lastBarrelSpawn = elapsedMs
    }

    private fun moveBarrels(dtMs: Double) {
        if (playerRespawning) return
        for (barrel in barrels) {
            if (barrel.bouncing) {
                barrel.vy += gravity
                var nextY = barrel.y + barrel.vy
                var bounced = false
                for (plat in platforms) {
                    if (abs(barrel.x - plat.x) < 3.5f && barrel.y >= plat.y && nextY <= plat.y) {
                        nextY = plat.y
                        barrel.vy = 0.4f + random.nextFloat() * 0.2f
                        bounced = true
                        break
                    }
                }
                if (!bounced && nextY <= 1) {
                    nextY = 1f
                    barrel.vy = 0.4f + random.nextFloat() * 0.2f
                }
                barrel.x += barrel.vx
                barrel.y = nextY
            } else {
                barrel.x += barrel.vx
                barrel.y = 1f
            }
            barrel.rotation += abs(barrel.vx) * 0.15f
            if (barrel.x < -55) {
                barrel.x = lastPlatformX
                barrel.y = if (random.nextBoolean()) 2f + random.nextFloat() * 2f else 1f
                barrel.vy = 0f
                barrel.bouncing = random.nextBoolean()
            }

            if (abs(playerX - barrel.x) < 1.2f && abs(playerY - barrel.y) < 1.5f) {
                explosions.add(Explosion(barrel.x, barrel.y))
                resetPlayerWithDelay()
            }
        }
    }

    private fun updatePlayerAnimation(mustStayCrouched: Boolean) {
        if (velX > 0) { facingRight = true; lastDirectionRight = true }
        else if (velX < 0) { facingRight = false; lastDirectionRight = false }
        else { facingRight = lastDirectionRight }

        val newAnim = when {
            (moveDown || mustStayCrouched) && canJump && abs(velY) < 0.001f -> "crouch"
            abs(velY) > 0.01f -> "jump"
            abs(velX) > 0.01f -> "run"
            else -> "idle"
        }

        if (newAnim != currentAnim) {
            currentAnim = newAnim
            animFrame = 0
            animFrameTime = 0
        }

        animFrameTime++
        if (animFrameTime >= 60 / animFrameRate) {
            animFrameTime = 0
            val sheet = playerSheets[getSheetName(currentAnim, facingRight)]
            val frameCount = if (sheet != null) sheet.cols * sheet.rows else 1
            animFrame = (animFrame + 1) % frameCount
        }
    }

    private fun getSheetName(anim: String, right: Boolean): String {
        val suffix = if (right) "right" else "left"
        return when (anim) {
            "idle" -> "standing$suffix"
            "run" -> "running$suffix"
            "jump" -> "jumping$suffix"
            "crouch" -> "crouching$suffix"
            "victory" -> "victory"
            else -> "standing$suffix"
        }
    }

    private fun triggerVictory() {
        if (won) return
        won = true
        currentAnim = "victory"
        animFrame = 0
        animFrameTime = 0
    }

    private fun updateVictoryAnimation() {
        animFrameTime++
        if (animFrameTime >= 60 / animFrameRate) {
            animFrameTime = 0
            val sheet = playerSheets["victory"]
            val frameCount = if (sheet != null) sheet.cols * sheet.rows else 1
            animFrame = (animFrame + 1) % frameCount
        }
    }

    private fun resetPlayerToStart() {
        playerX = -35f; playerY = 1f
        velX = 0f; velY = 0f
        canJump = true
        keyMoveLeft = false; keyMoveRight = false; keyMoveDown = false; touchMoveLeft = false; touchMoveRight = false; touchMoveDown = false
        playerRespawning = false
        barrels.clear()
        bombs.clear()
        lastBarrelSpawn = elapsedMs
        lastBombDrop = elapsedMs
    }

    private fun resetPlayerWithDelay() {
        if (playerRespawning) return
        playerRespawning = true
        velX = 0f; velY = 0f
        keyMoveLeft = false; keyMoveRight = false; keyMoveDown = false; touchMoveLeft = false; touchMoveRight = false; touchMoveDown = false
        postDelayed({ resetPlayerToStart() }, 1000)
    }

    private fun draw() {
        val canvas = holder.lockCanvas() ?: return
        try {
            // Sky fallback fill, always drawn first so there are never gaps at the edges
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bgPaint)

            canvas.save()
            canvas.translate(width / 2f, height / 2f)
            canvas.scale(camScale, camScale)

            // Coordinate helpers: screenY is negative worldY
            fun getRect(x: Float, y: Float, w: Float, h: Float): RectF {
                val left = (x - w / 2 - camX) * S
                val right = (x + w / 2 - camX) * S
                val top = -(y + h / 2 - camY) * S
                val bottom = -(y - h / 2 - camY) * S
                return RectF(left, top, right, bottom)
            }

            // Backdrop: one large world-space image spanning the whole level (matches the
            // iOS original, which parents it under worldNode instead of tiling it) so the
            // non-seamless artwork never has to repeat and show a seam.
            if (backdropBitmap != null) {
                val bgRect = getRect(0f, 10f, 200f, 100f)
                canvas.drawBitmap(backdropBitmap!!, null, bgRect, bitmapPaint)
            }

            // Draw grounds
            for (g in grounds) {
                val rect = getRect(g.x, 0.5f, g.w, 1.0f)
                canvas.drawRoundRect(rect, 4f * S / 40f, 4f * S / 40f, groundPaint)
                val grassRect = getRect(g.x, 0.95f, g.w, 0.1f)
                canvas.drawRect(grassRect, grassPaint)
            }

            // Draw platforms
            for (p in platforms) {
                val rect = getRect(p.x, p.y - 0.25f, 6.0f, 0.5f)
                canvas.drawRoundRect(rect, 6f * S / 40f, 6f * S / 40f, platformPaint)
            }

            // Draw obstacles
            for (o in obstacles) {
                val rect = getRect(o.x, o.y + 0.5f, 1.0f, 1.0f)
                canvas.drawRoundRect(rect, 3f * S / 40f, 3f * S / 40f, obstaclePaint)
            }

            // Draw bad guy (stationary barrel-thrower NPC on the last platform)
            playerSheets["badguy"]?.let { badGuySheet ->
                val bgRect = getRect(badGuyX, badGuyY + 1.0f, 2.0f, 2.0f)
                drawBitmapFrame(canvas, badGuySheet, badGuyFrame, bgRect)
            }

            // Draw player
            val sheetName = getSheetName(currentAnim, facingRight)
            val sheet = playerSheets[sheetName]
            if (sheet != null) {
                val pRect = getRect(playerX, playerY + 1.2f, 3.0f, 2.4f)
                drawBitmapFrame(canvas, sheet, animFrame, pRect)
            } else {
                val pRect = getRect(playerX, playerY + 1.2f, 1.8f, 2.4f)
                val pPaint = Paint().apply { color = Color.RED }
                canvas.drawRect(pRect, pPaint)
            }

            // Draw plane
            if (planeBitmap != null) {
                val pRect = getRect(planeX, planeY, 8.0f, 3.0f)
                canvas.save()
                canvas.scale(planeDir, 1f, (planeX - camX) * S, -(planeY - camY) * S)
                canvas.drawBitmap(planeBitmap!!, null, pRect, bitmapPaint)
                canvas.restore()
            }

            // Draw bombs
            for (bomb in bombs) {
                if (bombBitmap != null) {
                    val bRect = getRect(bomb.x, bomb.y, 1.0f, 2.4f)
                    canvas.drawBitmap(bombBitmap!!, null, bRect, bitmapPaint)
                }
            }

            // Draw barrels (rolling drum shape, matching the original)
            for (barrel in barrels) {
                canvas.save()
                canvas.translate((barrel.x - camX) * S, -(barrel.y + 0.7f - camY) * S)
                canvas.rotate(Math.toDegrees(barrel.rotation.toDouble()).toFloat())
                canvas.drawCircle(0f, 0f, 0.7f * S, barrelBodyPaint)
                canvas.drawCircle(0f, 0f, 0.7f * S, barrelStrokePaint)
                canvas.drawRect(-0.1f * S, -0.7f * S, 0.1f * S, 0.7f * S, barrelStripePaint)
                canvas.restore()
            }

            // Draw Explosions
            if (explosionSheet != null) {
                for (e in explosions) {
                    val eRect = getRect(e.x, e.y, 4.0f, 4.0f)
                    drawBitmapFrame(canvas, explosionSheet!!, e.frame, eRect)
                }
            }

            canvas.restore()

            // Draw UI
            if (started && !won) {
                drawButton(canvas, btnLeft, "L", moveLeft)
                drawButton(canvas, btnRight, "R", moveRight)
                drawButton(canvas, btnJump, "Jump", false)
                drawButton(canvas, btnCrouch, "Down", moveDown)
            }

            if (!started) {
                canvas.drawText("JASON'S GAME", width / 2f, height / 2f - 100f, textPaint)
                canvas.drawText("Tap to Start", width / 2f, height / 2f + 50f, textPaint)
            }
            if (won) {
                canvas.drawText("YOU WIN! 🎉", width / 2f, height / 2f, textPaint)
            }

        } finally {
            holder.unlockCanvasAndPost(canvas)
        }
    }
    
    private fun drawButton(canvas: Canvas, rect: RectF, label: String, pressed: Boolean) {
        uiButtonPaint.alpha = if (pressed) 150 else 80
        canvas.drawRoundRect(rect, 20f, 20f, uiButtonPaint)
        canvas.drawRoundRect(rect, 20f, 20f, uiButtonStrokePaint)
        canvas.drawText(label, rect.centerX(), rect.centerY() + 15f, uiTextPaint)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (!started) {
            startGame()
            return true
        }
        when (keyCode) {
            KeyEvent.KEYCODE_A, KeyEvent.KEYCODE_DPAD_LEFT -> keyMoveLeft = true
            KeyEvent.KEYCODE_D, KeyEvent.KEYCODE_DPAD_RIGHT -> keyMoveRight = true
            KeyEvent.KEYCODE_W, KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_SPACE -> doJump()
            KeyEvent.KEYCODE_S, KeyEvent.KEYCODE_DPAD_DOWN -> keyMoveDown = true
        }
        return true
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_A, KeyEvent.KEYCODE_DPAD_LEFT -> keyMoveLeft = false
            KeyEvent.KEYCODE_D, KeyEvent.KEYCODE_DPAD_RIGHT -> keyMoveRight = false
            KeyEvent.KEYCODE_S, KeyEvent.KEYCODE_DPAD_DOWN -> keyMoveDown = false
        }
        return true
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!started) {
            if (event.action == MotionEvent.ACTION_UP) startGame()
            return true
        }
        if (won) {
            if (event.action == MotionEvent.ACTION_UP) started = false
            return true
        }
        
        val count = event.pointerCount
        val action = event.actionMasked
        
        // Reset flags and re-evaluate based on all pointers
        var nextMoveLeft = false
        var nextMoveRight = false
        var nextMoveDown = false
        
        for (i in 0 until count) {
            val px = event.getX(i)
            val py = event.getY(i)
            
            // For ACTION_UP/POINTER_UP, skip the pointer that was released
            if ((action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_POINTER_UP) && 
                i == event.actionIndex) continue
                
            if (btnLeft.contains(px, py)) nextMoveLeft = true
            if (btnRight.contains(px, py)) nextMoveRight = true
            if (btnCrouch.contains(px, py)) nextMoveDown = true
            
            if (action == MotionEvent.ACTION_DOWN || action == MotionEvent.ACTION_POINTER_DOWN) {
                if (i == event.actionIndex && btnJump.contains(px, py)) doJump()
            }
        }
        
        touchMoveLeft = nextMoveLeft
        touchMoveRight = nextMoveRight
        touchMoveDown = nextMoveDown

        return true
    }


    private fun doJump() {
        if (canJump && !won && !playerRespawning) {
            velY = jumpStrength
            canJump = false
        }
    }
}
