const td = new TextDecoder()

/**
* @param {ArrayBuffer} memoryBuf 
* @param {number} ptr 
* @returns {string}
*/
function readColor(memoryBuf, ptr) {
    const buf = new Float32Array(memoryBuf, ptr, 4)
    const r = buf[0] * 255
    const g = buf[1] * 255
    const b = buf[2] * 255
    const a = buf[3] * 100
    return `rgb(${r} ${g} ${b} / ${a}%)`
}

/**
* @param {ArrayBuffer} memoryBuf 
* @param {number} ptr 
* @param {number} len
* @returns {string}
*/
function readString(memoryBuf, ptr, len) {
    const buf = new Uint8Array(memoryBuf, ptr, len)
    return td.decode(buf)
}

/**
* @param {ArrayBuffer} memoryBuf 
* @param {number} ptr 
* @returns {Float32Array}
*/
function readVec2(memoryBuf, ptr) {
    return new Float32Array(memoryBuf, ptr, 2)
}

async function main() {
    /** @type {HTMLCanvasElement} */
    const canvas = document.getElementById("canvas")
    if (!canvas) {
        throw Error("Missing canvas")
    }
    const canvasCtx = canvas.getContext("2d")
    if (!canvasCtx) {
        throw Error("Missing canvas context")
    }

    // state

    let canvasWidth = 0, canvasHeight = 0

    /**
    * @param {HTMLCanvasElement} canvas
    * @param {CanvasRenderingContext2D} ctx
    */
    function resizeCanvas(canvas) {
        const rect = canvas.getBoundingClientRect()

        canvasWidth = Math.round(rect.width)
        canvasHeight = Math.round(rect.height)

        if (canvas.width != canvasWidth || canvas.height != canvasHeight) {
            canvas.width = canvasWidth
            canvas.height = canvasHeight
        }
    }

    let mousex = 0, mousey = 0, mouseBtn = 0
    window.addEventListener("mousemove", function(/** @type {MouseEvent} */e) {
        mousex = e.x
        mousey = e.y
    })
    window.addEventListener("mousedown", function(/** @type {MouseEvent} */e) {
        mousex = e.x
        mousey = e.y
        mouseBtn = e.buttons
    })
    window.addEventListener("mouseup", function(/** @type {MouseEvent} */e) {
        mousex = e.x
        mousey = e.y
        mouseBtn = e.buttons
    })

    const maxEventsCount = 512
    /** @type {ArrayBuffer[]} */
    const events = []

    /**
    * @param {ArrayBuffer} raw
    */
    function appendEvent(raw) {
        if (events.length === maxEventsCount) {
            events.shift()
        }
        events.push(raw)
    }

    /**
    * @param {KeyboardEvent} e
    * @param {number} t
    */
    function keyboardEvent(e, t) {
        const eventRaw = new ArrayBuffer(4)
        const view = new DataView(eventRaw)
        view.setUint8(0, t)

        switch (e.key) {
            case "ArrowUp":
                view.setUint16(1, 1)
                break
            case "ArrowDown":
                view.setUint16(1, 2)
                break
            case "ArrowLeft":
                view.setUint16(1, 3)
                break
            case "ArrowRight":
                view.setUint16(1, 4)
                break
            case "Escape":
                view.setUint16(1, 5)
                break
            default:
                return
        }

        appendEvent(eventRaw)
    }

    window.addEventListener("keydown", function(/** @type {KeyboardEvent} */e) {
        keyboardEvent(e, 2)
    })
    window.addEventListener("keyup", function(/** @type {KeyboardEvent} */e) {
        keyboardEvent(e, 3)
    })

    window.addEventListener("resize", function() {
        resizeCanvas(canvas, canvasCtx)

        const eventRaw = new ArrayBuffer(4 + 8)
        const view = new DataView(eventRaw)
        view.setUint8(0, 1)
        view.setFloat32(4, canvasWidth, true)
        view.setFloat32(8, canvasHeight, true)
        appendEvent(eventRaw)
    })


    // load textures

    const spritesPath = "/static/sprites.png"
    const sprites = new Image()
    sprites.src = spritesPath

    // load font

    /**
    * @typedef {{width: number; height: number;} FontMetrics
    *
    * @param {number} size
    * @returns {Promise<{ name: string, char: FontMetrics, charMap: FontMetrics[] }>}
    */
    async function loadFont(size) {
        const font = `${size}px editundo`
        await document.fonts.load(font)

        let maxWidth = 0
        let maxHeight = 0

        /** @type {FontMetrics[]} */
        const chars = []

        for (let c = 32; c < 127; c += 1) {
            canvasCtx.font = font
            canvasCtx.textBaseline = "top"
            canvasCtx.textAlign = "left"
            const text = String.fromCharCode(c)
            const tm = canvasCtx.measureText(text)

            maxWidth = Math.max(maxWidth, tm.width)
            maxHeight = Math.max(maxHeight, tm.fontBoundingBoxDescent)

            chars[c] = { width: tm.width, height: tm.height }
        }

        return { name: font, char: { width: maxWidth, height: maxHeight }, charMap: chars }
    }

    const font = await loadFont(20)

    // load wasm 

    const wasmPath = "/static/game.wasm"
    const wasmRes = await fetch(wasmPath)
    const wasmBytes = await wasmRes.arrayBuffer()

    let targetFrameTime = 1 / 144
    let actualFrameTime = 0

    /** @type {ArrayBuffer} */
    let memory
    /** @type {DataView} */
    let memView

    const env = {
        odin_env: {
            write(fd, ptr, len) {
                if (len == 0) {
                    return
                }
                const data = new Uint8Array(memory, ptr, len)
                let str
                let print
                if (fd == 1) {
                    print = console.log
                    str = td.decode(data)
                } else if (fd == 2) {
                    print = console.error
                    str = td.decode(data)
                }

                if (str != "" && str.trim() != "") {
                    print(str)
                }
            },
            tick_now() {
                return performance.now()
            },
            rand_bytes(ptr, len) {
                const view = new Uint8Array(memory, ptr, len)
                crypto.getRandomValues(view)
            },
        },
        env: {
            set_target_fps(fps) {
                targetFrameTime = 1 / fps
            },
            get_actual_fps(fps_ptr) {
                memView.setFloat32(fps_ptr, 1 / actualFrameTime, true)
            },
            window_size(ptr) {
                const vec2 = new Float32Array(memory, ptr, 2)
                vec2[0] = canvasWidth
                vec2[1] = canvasHeight
            },
            draw_image(src_rect_ptr, dst_rect_ptr) {
                const src_rect = new Float32Array(memory, src_rect_ptr, 4)
                const dst_rect = new Float32Array(memory, dst_rect_ptr, 4)

                canvasCtx.drawImage(
                    sprites,
                    src_rect[0],
                    src_rect[1],
                    src_rect[2],
                    src_rect[3],
                    dst_rect[0],
                    dst_rect[1],
                    dst_rect[2],
                    dst_rect[3],
                )
            },
            draw_rect(rect_ptr, color_ptr) {
                const rect = new Float32Array(memory, rect_ptr, 4)
                canvasCtx.strokeStyle = readColor(memory, color_ptr)
                canvasCtx.strokeRect(rect[0], rect[1], rect[2], rect[3])
            },
            fill_rect(rect_ptr, color_ptr) {
                const rect = new Float32Array(memory, rect_ptr, 4)
                canvasCtx.fillStyle = readColor(memory, color_ptr)
                canvasCtx.fillRect(rect[0], rect[1], rect[2], rect[3])
            },
            measure_text(size_ptr, text_ptr, text_len) {
                const size = new Float32Array(memory, size_ptr, 2)

                const text = readString(memory, text_ptr, text_len)
                canvasCtx.font = font.name
                canvasCtx.textBaseline = "top"
                canvasCtx.textAlign = "left"
                const m = canvasCtx.measureText(text)

                size[0] = m.width
                size[1] = m.fontBoundingBoxDescent
            },
            font_metrics_max(size_ptr) {
                const size = new Float32Array(memory, size_ptr, 2)
                size[0] = font.char.width
                size[1] = font.char.height
            },
            fill_text(pos_ptr, color_ptr, text_ptr, text_len) {
                const pos = readVec2(memory, pos_ptr)
                const text = readString(memory, text_ptr, text_len)

                canvasCtx.font = font.name
                canvasCtx.textBaseline = "top"
                canvasCtx.textAlign = "left"
                canvasCtx.fillStyle = readColor(memory, color_ptr)
                canvasCtx.fillText(text, pos[0], pos[1])
            },
            stroke_text(pos_ptr, color_ptr, text_ptr, text_len) {
                const pos = readVec2(memory, pos_ptr)
                const text = readString(memory, text_ptr, text_len)

                canvasCtx.font = font.name
                canvasCtx.textBaseline = "top"
                canvasCtx.textAlign = "left"
                canvasCtx.strokeStyle = readColor(memory, color_ptr)
                canvasCtx.strokeText(text, pos[0], pos[1])
            },
            get_mouse_state(x_ptr, y_ptr, btn_ptr) {
                memView.setFloat32(x_ptr, mousex, true)
                memView.setFloat32(y_ptr, mousey, true)
                memView.setUint8(btn_ptr, mouseBtn)
            },
            poll_event(event_ptr) {
                if (events.length > 0) {
                    const event = new Uint8Array(events.shift())

                    let i = 0
                    for (const b of event) {
                        memView.setUint8(event_ptr + i, b)
                        i += 1
                    }
                } else {
                    memView.setUint8(event_ptr, 0)
                }
            }
        },
    }

    const wa = await WebAssembly.instantiate(wasmBytes, env)
    const exports = wa.instance.exports
    memory = exports.memory.buffer
    memView = new DataView(memory)

    // init

    resizeCanvas(canvas, canvasCtx)

    if (exports.init) {
        exports.init()
    }

    // run

    let prevTimestamp = 0

    /** @param {number} currTimestamp */
    async function step(currTimestamp) {
        if (prevTimestamp == 0) {
            prevTimestamp = currTimestamp
        }

        const dt = (currTimestamp - prevTimestamp) * 0.001
        prevTimestamp = currTimestamp

        const frameStart = performance.now()

        canvasCtx.clearRect(0, 0, canvasWidth, canvasHeight)

        if (exports.step) {
            const _continue = exports.step(dt)
            if (!_continue) {
                return
            }
        }

        const frameEnd = performance.now()
        const frameDuration = (frameEnd - frameStart) / 1000
        const remaining = targetFrameTime - frameDuration
        if (remaining > 0) {
            await new Promise(function(res) {
                setTimeout(function() {
                    res()
                }, remaining * 1000)
            })
        }

        actualFrameTime = (frameDuration + remaining)

        requestAnimationFrame(step)
    }

    requestAnimationFrame(step)
}

document.addEventListener("DOMContentLoaded", main)
