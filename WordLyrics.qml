import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    // DMS 1.6 doesn't inject editMode (the plugin README still mentions it);
    // declare it so references don't throw and it starts working if DMS adds it.
    property bool editMode: false

    minWidth: 280
    minHeight: 160
    property real defaultWidth: 640
    property real defaultHeight: 440

    // ── settings ────────────────────────────────────────────────────────────
    readonly property int fontSize: pluginData.fontSize ?? 34
    readonly property string fontFamilySetting: pluginData.fontFamily ?? ""
    readonly property string textAlign: pluginData.textAlign ?? "left"
    readonly property real anchorPos: parseFloat(pluginData.anchorPos ?? "0.33")
    readonly property int offsetMs: pluginData.offsetMs ?? 0
    readonly property bool blurInactive: pluginData.blurInactive ?? true
    readonly property bool shadowOn: pluginData.textShadow ?? true
    readonly property bool edgeFade: pluginData.edgeFade ?? true
    readonly property real fadeTopPct: (pluginData.fadeTop ?? 30) / 100
    readonly property real fadeBottomPct: (pluginData.fadeBottom ?? 18) / 100
    readonly property string colorMode: pluginData.colorMode ?? "white"
    readonly property real dimAlpha: (pluginData.dimOpacity ?? 35) / 100
    readonly property string scrollCurve: pluginData.scrollCurve ?? "easeInOut"
    readonly property int scrollDuration: pluginData.scrollDuration ?? 700
    readonly property int scrollStagger: pluginData.scrollStagger ?? 45
    readonly property int scrollLeadMs: pluginData.scrollLead ?? 250
    readonly property int scrollEasing: ({
            "easeInOut": Easing.InOutCubic,
            "sine": Easing.InOutSine,
            "expressive": Easing.InOutQuart,
            "apple": Easing.BezierSpline
        })[scrollCurve] ?? Easing.InOutCubic
    // Apple's "ease-in-out" timing curve (CAMediaTimingFunction easeInEaseOut)
    readonly property var scrollBezier: [0.42, 0.0, 0.58, 1.0, 1.0, 1.0]
    readonly property bool hideWhenPaused: pluginData.hideWhenPaused ?? false
    readonly property string preferredPlayer: pluginData.preferredPlayer ?? ""
    readonly property string mxmToken: pluginData.musixmatchToken ?? ""

    readonly property int hAlign: textAlign === "center" ? Text.AlignHCenter : textAlign === "right" ? Text.AlignRight : Text.AlignLeft
    readonly property color textColor: colorMode === "primary" ? Theme.primary : colorMode === "surface" ? Theme.surfaceText : "#ffffff"
    readonly property string fontFamily: fontFamilySetting !== "" ? fontFamilySetting : Theme.fontFamily
    readonly property real rowH: fontSize * 1.22
    readonly property real lineGap: fontSize * 0.62
    readonly property real liftPx: fontSize * 0.07
    readonly property real sidePad: Math.max(12, fontSize * 0.4)

    readonly property string scriptPath: decodeURIComponent(Qt.resolvedUrl("lyrics.py").toString().replace(/^file:\/\//, ""))
    readonly property url shaderUrl: Qt.resolvedUrl("shaders/wordfill.frag.qsb")

    // ── player ──────────────────────────────────────────────────────────────
    readonly property var player: {
        const pref = preferredPlayer.toLowerCase().trim();
        if (pref) {
            const m = Mpris.players.values.find(p => [p.identity, p.desktopEntry, p.dbusName].some(s => String(s ?? "").toLowerCase().includes(pref)));
            if (m)
                return m;
        }
        return MprisController.activePlayer;
    }
    readonly property string trackTitle: player?.trackTitle ?? ""
    readonly property string trackArtist: player?.trackArtist ?? ""
    readonly property bool isPlaying: player?.isPlaying ?? false
    readonly property bool hasMedia: !!player && trackTitle !== "" && player.playbackState !== MprisPlaybackState.Stopped

    // ── lyrics state ────────────────────────────────────────────────────────
    property var lines: []
    property string lyricSource: ""
    property string lyricKind: ""
    property string status: "idle"   // idle | loading | ok | notfound | error
    property string loadedKey: ""
    property real pos: 0
    property int activeIndex: -1

    signal shifted(real dy)

    function trackKeyNow() {
        return player ? (trackTitle + "\u0001" + trackArtist) : "";
    }

    onTrackTitleChanged: {
        _haveBase = false;
        fetchDebounce.restart();
    }
    onTrackArtistChanged: fetchDebounce.restart()
    onPlayerChanged: fetchDebounce.restart()
    onMxmTokenChanged: fetchDebounce.restart()

    Timer {
        id: retryTimer
        property int attempts: 0
        interval: 15000
        onTriggered: root.requestLyrics()
    }

    Timer {
        id: fetchDebounce
        interval: 450
        onTriggered: root.requestLyrics()
    }

    function requestLyrics() {
        const key = trackKeyNow();
        if (!key || !trackTitle) {
            setLines([], "idle");
            loadedKey = "";
            return;
        }
        if (key === loadedKey && status !== "error")
            return;
        if (key !== loadedKey)
            retryTimer.attempts = 0;
        loadedKey = key;
        setLines([], "loading");
        const cmd = ["python3", scriptPath, "--key", key, "--title", trackTitle, "--artist", trackArtist, "--album", player.trackAlbum ?? "", "--duration", String(player.length > 0 ? player.length : 0)];
        if (mxmToken)
            cmd.push("--mxm-token", mxmToken);
        // One process per request: restarting a shared Process races with the
        // old one's exit and its empty stdout. Stale ones just get ignored.
        const proc = fetchComp.createObject(root, { reqKey: key, command: cmd });
        proc.running = true;
    }

    function onFetched(reqKey, text, exitCode) {
        if (reqKey !== loadedKey)
            return; // stale response for a previous track
        let d;
        try {
            d = JSON.parse(text);
        } catch (e) {
            console.warn(`[WordLyrics] helper failed (exit ${exitCode}):`, text.slice(0, 200));
            d = { ok: false, details: ["helper exit " + exitCode] };
        }
        if (!d.ok) {
            const transient = (d.details ?? []).length > 0;
            console.info(`[WordLyrics] no lyrics for "${trackTitle}"${transient ? " (source errors: " + d.details.join("; ") + ")" : ""}`);
            setLines([], transient ? "error" : "notfound");
            if (transient && retryTimer.attempts < 3) {
                retryTimer.attempts++;
                retryTimer.restart();
            }
            return;
        }
        retryTimer.attempts = 0;
        lyricSource = d.source;
        lyricKind = d.kind;
        setLines(d.lines, "ok");
        console.info(`[WordLyrics] ${d.lines.length} lines from ${d.source} (${d.kind})${d.cached ? " [cache]" : ""}`);
    }

    function setLines(l, st) {
        jumpTimer.restart(); // snap scroll while the new layout settles
        activeIndex = -1;
        lines = l;
        status = st;
        tick();
    }

    Component {
        id: fetchComp
        Process {
            id: proc
            property string reqKey: ""
            property string out: ""
            property bool outDone: false
            property int exitCode: -1
            property bool exited: false

            function finishIfReady() {
                if (!outDone || !exited)
                    return;
                root.onFetched(reqKey, out, exitCode);
                destroy();
            }

            stdout: StdioCollector {
                onStreamFinished: {
                    proc.out = text;
                    proc.outDone = true;
                    proc.finishIfReady();
                }
            }
            stderr: StdioCollector {
                onStreamFinished: if (text.trim())
                    console.warn("[WordLyrics] helper:", text.trim())
            }
            onExited: code => {
                exitCode = code;
                exited = true;
                finishIfReady();
            }
        }
    }

    // ── timing ──────────────────────────────────────────────────────────────
    function tick() {
        if (!player)
            return;
        pos = playerPos() + offsetMs / 1000;
        // the active line switches (and starts scrolling) a bit before it's sung;
        // word fill still follows the real position
        const at = pos + scrollLeadMs / 1000;
        const L = lines;
        let i = activeIndex;
        if (i >= L.length || (i >= 0 && L[i].t > at) || i < -1) {
            let lo = 0, hi = L.length - 1;
            i = -1;
            while (lo <= hi) {
                const mid = (lo + hi) >> 1;
                if (L[mid].t <= at) {
                    i = mid;
                    lo = mid + 1;
                } else {
                    hi = mid - 1;
                }
            }
        } else {
            while (i + 1 < L.length && L[i + 1].t <= at)
                i++;
        }
        if (i !== activeIndex)
            activeIndex = i;
    }

    FrameAnimation {
        running: root.isPlaying && root.lines.length > 0 && root.opacity > 0
        onTriggered: root.tick()
    }

    Connections {
        target: root.player
        function onPositionChanged() {
            root.tick();
        }
    }

    function seekTo(t) {
        if (!player || !player.canSeek)
            return;
        const target = Math.max(0, t - offsetMs / 1000 + 0.02);
        player.position = target;
        syncBase(target);
        tick();
        posPoll.restart();
    }

    // ── position source ─────────────────────────────────────────────────────
    // Quickshell's MprisPlayer.position can't be trusted for every player
    // (Cassette sends Seeked in seconds instead of µs, so it reads ~0). We poll
    // the Position property over D-Bus once a second and interpolate locally.
    property real _basePos: 0
    property real _baseTime: 0
    property bool _haveBase: false

    function playerPos() {
        if (!_haveBase)
            return player ? player.position : 0;
        return _basePos + (isPlaying ? (Date.now() - _baseTime) / 1000 : 0);
    }

    function syncBase(p) {
        _basePos = p;
        _baseTime = Date.now();
        _haveBase = true;
    }

    onIsPlayingChanged: {
        if (_haveBase)
            syncBase(_basePos + (!isPlaying ? (Date.now() - _baseTime) / 1000 : 0));
        posPoll.restart();
        pollPosition();
    }

    function pollPosition() {
        if (!player || !player.dbusName || posProc.running)
            return;
        posProc.startedAt = Date.now();
        posProc.command = ["busctl", "--user", "get-property", player.dbusName, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Position"];
        posProc.running = true;
    }

    Timer {
        id: posPoll
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: !!root.player && root.lines.length > 0 && root.opacity > 0
        onTriggered: root.pollPosition()
    }

    Process {
        id: posProc
        property real startedAt: 0
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/^x\s+(-?\d+)/);
                if (!m)
                    return;
                const now = Date.now();
                // the value was sampled somewhere during the call: assume the midpoint
                const measured = parseInt(m[1]) / 1e6 + (root.isPlaying ? (now - posProc.startedAt) / 2000 : 0);
                const predicted = root.playerPos();
                const err = measured - predicted;
                if (!root._haveBase || Math.abs(err) > 0.3)
                    root.syncBase(measured); // seek / track change: jump
                else
                    root.syncBase(predicted + err * 0.35); // small drift: slew gently
                root.tick();
            }
        }
    }

    function wordProgress(w, p) {
        if (p <= w.s)
            return 0;
        if (p >= w.e)
            return 1;
        if (!w.p)
            return (p - w.s) / Math.max(0.001, w.e - w.s);
        let total = 0, done = 0;
        for (const part of w.p)
            total += part[0];
        for (const part of w.p) {
            if (p >= part[2])
                done += part[0];
            else if (p > part[1])
                done += part[0] * (p - part[1]) / Math.max(0.001, part[2] - part[1]);
        }
        return Math.min(1, done / total);
    }

    function easeOut(x) {
        return 1 - Math.pow(1 - Math.max(0, Math.min(1, x)), 3);
    }

    TextMetrics {
        id: spaceMetrics
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        font.weight: Font.Bold
        text: " "
    }

    // ── visibility ──────────────────────────────────────────────────────────
    opacity: editMode || (hasMedia && (!hideWhenPaused || isPlaying)) ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }

    // ── status (no lyrics) ──────────────────────────────────────────────────
    Text {
        anchors.centerIn: parent
        width: parent.width - root.sidePad * 2
        visible: root.lines.length === 0
        horizontalAlignment: root.hAlign
        wrapMode: Text.WordWrap
        font.family: root.fontFamily
        font.pixelSize: Math.max(14, root.fontSize * 0.5)
        font.weight: Font.DemiBold
        color: root.textColor
        opacity: 0.55
        style: root.shadowOn ? Text.Raised : Text.Normal
        styleColor: "#60000000"
        text: {
            if (root.status === "loading")
                return "Ищу текст…";
            if (root.status === "notfound")
                return "Текст не найден\n" + root.trackTitle;
            if (root.status === "error")
                return "Ошибка загрузки текста";
            if (root.trackTitle)
                return root.trackTitle;
            return root.editMode ? "Word Lyrics" : "";
        }
    }

    // ── lyrics viewport ─────────────────────────────────────────────────────
    Item {
        id: viewport
        anchors.fill: parent
        clip: true
        visible: root.lines.length > 0

        // Two nested layers: the inner one draws the text shadow, the outer one
        // fades the result to transparent towards the top and bottom edges.
        layer.enabled: root.edgeFade
        layer.effect: ShaderEffect {
            property real fadeTop: root.fadeTopPx / Math.max(1, viewport.height)
            property real fadeBottom: root.fadeBottomPx / Math.max(1, viewport.height)
            fragmentShader: Qt.resolvedUrl("shaders/edgefade.frag.qsb")
        }

        Item {
            id: shadowBox
            anchors.fill: parent

            layer.enabled: root.shadowOn
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowOpacity: 0.45
                shadowBlur: 0.45
                shadowVerticalOffset: 1
                shadowHorizontalOffset: 0
                blurMax: 12
            }

            Column {
                id: col
                x: root.sidePad
                width: parent.width - root.sidePad * 2
                spacing: 0

                Repeater {
                    id: lineRep
                    model: root.lines
                    delegate: LyricLine {}
                }
            }
        }
    }

    // Top fade never reaches into the active line: it ends where that line starts
    // (measured at its resting position, not mid-animation).
    readonly property real fadeTopPx: {
        const want = viewport.height * fadeTopPct;
        const idx = Math.max(0, activeIndex);
        const it = lineRep.count > idx ? lineRep.itemAt(idx) : null;
        if (!it)
            return want;
        const activeTop = colTargetY + it.y - lineGap * 0.25;
        return Math.max(0, Math.min(want, activeTop));
    }
    readonly property real fadeBottomPx: viewport.height * fadeBottomPct

    // Scroll: the column jumps to its target instantly, every line then gets a
    // compensating offset that springs back to 0 with a per-line delay.
    readonly property real colTargetY: {
        const idx = Math.max(0, activeIndex);
        if (lineRep.count <= idx)
            return viewport.height * anchorPos;
        const it = lineRep.itemAt(idx);
        if (!it)
            return viewport.height * anchorPos;
        return viewport.height * anchorPos - (it.y + it.height / 2);
    }

    property int _scrollIndex: -2

    onColTargetYChanged: {
        const dy = col.y - colTargetY;
        col.y = colTargetY;
        const lineChanged = activeIndex !== _scrollIndex;
        _scrollIndex = activeIndex;
        // Only a change of the active line starts the cascade. Layout changes
        // (an interlude collapsing, resize) just move the column: they are
        // already animated by their own Behaviors or should follow instantly.
        if (lineChanged && !jumpTimer.running && !editMode && Math.abs(dy) > 0.5)
            shifted(dy);
    }

    Timer {
        id: jumpTimer
        interval: 250
    }

    // ── line delegate ───────────────────────────────────────────────────────
    component LyricLine: Item {
        id: line

        required property var modelData
        required property int index

        readonly property bool isGap: !!modelData.gap
        readonly property bool isActive: index === root.activeIndex
        // root.pos is only read for the line right above the active one, so other
        // lines don't re-evaluate every frame
        readonly property bool filling: !isGap && (isActive || (index === root.activeIndex - 1 && root.pos < modelData.e))
        readonly property int dist: root.activeIndex < 0 ? index + 1 : Math.abs(index - root.activeIndex)
        readonly property real gapProgress: isGap && isActive ? Math.max(0, Math.min(1, (root.pos - modelData.t) / Math.max(0.1, modelData.e - modelData.t))) : 0
        readonly property bool hovered: hover.containsMouse

        width: col.width
        height: isGap ? (isActive ? root.rowH * 1.1 + root.lineGap : 0) : wordsBox.height + root.lineGap
        clip: isGap

        Behavior on height {
            enabled: line.isGap
            NumberAnimation {
                duration: 420
                easing.type: Easing.OutCubic
            }
        }

        transform: Translate {
            id: shift
        }

        Connections {
            target: root
            function onShifted(dy) {
                const wasMoving = scrollAnim.running || springScroll.running;
                scrollAnim.stop();
                springScroll.stop();
                const rel = line.index - Math.max(0, root.activeIndex);
                // offscreen lines don't need to animate
                const sy = col.y + line.y + shift.y + dy;
                if (sy > viewport.height * 2 || sy + line.height < -viewport.height) {
                    shift.y = 0;
                    return;
                }
                shift.y += dy;
                // wave: lines below the new active one start a little later
                const delay = wasMoving ? 0 : Math.max(0, Math.min(7, rel + 1)) * root.scrollStagger;
                if (root.scrollCurve === "spring") {
                    springScroll.delayMs = delay;
                    springScroll.start();
                } else {
                    scrollAnim.delayMs = delay;
                    // a line interrupted mid-move must not stop dead and ease in again
                    scrollAnim.interrupted = wasMoving;
                    scrollAnim.start();
                }
            }
        }

        SequentialAnimation {
            id: scrollAnim
            property int delayMs: 0
            property bool interrupted: false
            PauseAnimation {
                duration: scrollAnim.delayMs
            }
            NumberAnimation {
                target: shift
                property: "y"
                to: 0
                duration: root.scrollDuration
                easing.type: scrollAnim.interrupted ? Easing.OutCubic : root.scrollEasing
                easing.bezierCurve: root.scrollBezier
            }
        }

        SequentialAnimation {
            id: springScroll
            property int delayMs: 0
            PauseAnimation {
                duration: springScroll.delayMs
            }
            SpringAnimation {
                target: shift
                property: "y"
                to: 0
                spring: 2.6 * 700 / Math.max(200, root.scrollDuration)
                damping: 0.32
                mass: 1.0
                epsilon: 0.25
            }
        }

        // hover highlight
        Rectangle {
            x: -root.sidePad * 0.6
            y: -root.lineGap * 0.3
            width: line.width + root.sidePad * 1.2
            height: wordsBox.height + root.lineGap * 0.6
            radius: Math.min(18, root.fontSize * 0.45)
            color: root.textColor
            opacity: line.hovered && !line.isGap ? 0.08 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                }
            }
        }

        // ── words ──
        Item {
            id: wordsBox
            visible: !line.isGap
            width: line.width
            height: line.isGap ? 0 : Math.max(1, layout.rows) * root.rowH

            // A line that starts filling is fully opaque at once: its unsung words are
            // already dimmed by the shader, so there's no jump, and the sweep is
            // visible from the first frame instead of after a fade-in.
            // Fading out (line done) stays animated via fadeOpacity.
            opacity: line.filling ? 1 : fadeOpacity
            property real fadeOpacity: line.filling ? 1 : Math.max(0.22, root.dimAlpha * (line.hovered ? 1.9 : (1 - 0.1 * Math.max(0, line.dist - 1))))
            Behavior on fadeOpacity {
                NumberAnimation {
                    duration: 380
                    easing.type: Easing.OutCubic
                }
            }

            readonly property bool blurred: root.blurInactive && !line.filling && !line.hovered && !root.editMode
            layer.enabled: blurred
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 16
                blur: Math.min(1, 0.12 + 0.11 * Math.max(0, line.dist - 1))
                autoPaddingEnabled: true
            }

            // word wrapping with alignment (Flow can't center rows)
            readonly property var layout: {
                const n = wordRep.count;
                const avail = width;
                const pos = [];
                const rowW = []; // visible width of each row, trailing space excluded
                let x = 0, row = 0, lastVisible = 0;
                for (let i = 0; i < n; i++) {
                    const it = wordRep.itemAt(i);
                    const w = it ? it.implicitWidth : 0;
                    const tw = it ? it.textWidth : 0;
                    if (x > 0 && x + tw > avail) {
                        rowW.push(lastVisible);
                        row++;
                        x = 0;
                    }
                    pos.push({ x: x, row: row });
                    lastVisible = x + tw;
                    x += w;
                }
                rowW.push(lastVisible);
                for (let i = 0; i < pos.length; i++) {
                    const free = Math.max(0, avail - rowW[pos[i].row]);
                    pos[i].x += root.textAlign === "center" ? free / 2 : root.textAlign === "right" ? free : 0;
                }
                return { pos: pos, rows: row + 1 };
            }

            Repeater {
                id: wordRep
                model: line.isGap ? [] : line.modelData.w
                delegate: LyricWord {
                    lineActive: line.filling
                    x: wordsBox.layout.pos[index]?.x ?? 0
                    y: (wordsBox.layout.pos[index]?.row ?? 0) * root.rowH
                }
            }
        }

        // ── interlude dots ──
        Row {
            id: dots
            visible: line.isGap
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -root.lineGap / 2
            x: root.textAlign === "center" ? (line.width - width) / 2 : root.textAlign === "right" ? line.width - width : root.fontSize * 0.1
            spacing: root.fontSize * 0.28
            transformOrigin: Item.Center
            scale: {
                if (!line.isActive)
                    return 0.6;
                const breathe = 1 + 0.09 * Math.sin(root.pos * Math.PI * 2 / 1.9);
                const tail = Math.max(0, Math.min(1, (line.modelData.e - root.pos) / 0.45));
                return breathe * (0.35 + 0.65 * root.easeOut(tail));
            }
            opacity: line.isActive ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 300
                }
            }

            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    readonly property real d: root.fontSize * 0.3
                    width: d
                    height: d
                    radius: d / 2
                    color: root.textColor
                    opacity: root.dimAlpha + (1 - root.dimAlpha) * Math.max(0, Math.min(1, line.gapProgress * 3 - index))
                }
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            enabled: !root.editMode && !line.isGap
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.seekTo(line.modelData.t)
        }
    }

    function spaceWidth() {
        return spaceMetrics.advanceWidth;
    }

    // ── word delegate ───────────────────────────────────────────────────────
    component LyricWord: Item {
        id: word

        required property var modelData
        required property int index
        property bool lineActive: false

        readonly property string txt: modelData.x.replace(/\s+$/, "")
        readonly property bool spaced: /\s$/.test(modelData.x)
        readonly property real textWidth: label.implicitWidth
        readonly property real dur: modelData.e - modelData.s
        readonly property bool held: dur >= 1.1 && txt.length <= 14
        // only read root.pos while our line is active, so idle lines don't re-evaluate every frame
        readonly property real progress: lineActive ? root.wordProgress(modelData, root.pos) : 0
        readonly property real glow: held && lineActive ? Math.sin(Math.PI * progress) : 0

        implicitWidth: label.implicitWidth + (spaced ? spaceMetrics.advanceWidth : 0)
        implicitHeight: root.rowH

        Text {
            id: label
            height: root.rowH
            verticalAlignment: Text.AlignVCenter
            text: word.txt
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            font.weight: Font.Bold
            color: root.textColor
            transformOrigin: Item.Bottom
            scale: 1 + 0.045 * word.glow

            transform: Translate {
                y: word.lineActive ? -root.liftPx * root.easeOut(word.progress * 1.6) : 0
                Behavior on y {
                    enabled: !word.lineActive
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                }
            }

            layer.enabled: word.lineActive
            layer.effect: ShaderEffect {
                readonly property real featherPx: root.fontSize * 0.45
                property real feather: Math.min(0.5, featherPx / Math.max(1, label.width) / 2)
                property real progress: -feather + word.progress * (1 + 2 * feather)
                property real dimAlpha: root.dimAlpha
                property real glow: word.glow
                fragmentShader: root.shaderUrl
            }
        }
    }

    Component.onCompleted: {
        fetchDebounce.restart();
        console.info("[WordLyrics] loaded, helper:", scriptPath);
    }
}
