import AppKit
import SwiftUI

/// Something new each day: a short quote from a science-fiction writer or a scientist, and a small ASCII animation,
/// both picked by the date, so they change at midnight and stay the same all day. Only well-sourced wording, with
/// famous misattributions left out.
enum Daily {
    struct Quote { let text: String; let author: String }

    static let quotes: [Quote] = [
        Quote(text: "Any sufficiently advanced technology is indistinguishable from magic.", author: "Arthur C. Clarke"),
        Quote(text: "The only way of discovering the limits of the possible is to venture a little way past them into the impossible.", author: "Arthur C. Clarke"),
        Quote(text: "The saddest aspect of life right now is that science gathers knowledge faster than society gathers wisdom.", author: "Isaac Asimov"),
        Quote(text: "Violence is the last refuge of the incompetent.", author: "Isaac Asimov, Foundation"),
        Quote(text: "It is good to have an end to journey toward; but it is the journey that matters, in the end.", author: "Ursula K. Le Guin"),
        Quote(text: "The only thing that makes life possible is permanent, intolerable uncertainty; not knowing what comes next.", author: "Ursula K. Le Guin"),
        Quote(text: "All that you touch you change. All that you change changes you.", author: "Octavia E. Butler, Parable of the Sower"),
        Quote(text: "First forget inspiration. Habit is more dependable.", author: "Octavia E. Butler"),
        Quote(text: "The future is already here — it's just not very evenly distributed.", author: "William Gibson"),
        Quote(text: "I must not fear. Fear is the mind-killer.", author: "Frank Herbert, Dune"),
        Quote(text: "The mystery of life isn't a problem to solve, but a reality to experience.", author: "Frank Herbert, Dune"),
        Quote(text: "I love deadlines. I love the whooshing noise they make as they go by.", author: "Douglas Adams"),
        Quote(text: "Don't Panic.", author: "Douglas Adams, The Hitchhiker's Guide to the Galaxy"),
        Quote(text: "Reality is that which, when you stop believing in it, doesn't go away.", author: "Philip K. Dick"),
        Quote(text: "We are what we pretend to be, so we must be careful about what we pretend to be.", author: "Kurt Vonnegut, Mother Night"),
        Quote(text: "Specialization is for insects.", author: "Robert A. Heinlein"),
        Quote(text: "Weakness and ignorance are not barriers to survival, but arrogance is.", author: "Liu Cixin, Death's End"),
        Quote(text: "The cosmos is within us. We are made of star-stuff.", author: "Carl Sagan, Cosmos"),
        Quote(text: "We are a way for the cosmos to know itself.", author: "Carl Sagan, Cosmos"),
        Quote(text: "Extraordinary claims require extraordinary evidence.", author: "Carl Sagan"),
        Quote(text: "The first principle is that you must not fool yourself — and you are the easiest person to fool.", author: "Richard Feynman"),
        Quote(text: "What I cannot create, I do not understand.", author: "Richard Feynman"),
        Quote(text: "The eternal mystery of the world is its comprehensibility.", author: "Albert Einstein"),
        Quote(text: "Imagination is more important than knowledge.", author: "Albert Einstein"),
        Quote(text: "Nothing in life is to be feared, it is only to be understood.", author: "Marie Curie"),
        Quote(text: "How wonderful that we have met with a paradox. Now we have some hope of making progress.", author: "Niels Bohr"),
        Quote(text: "Look up at the stars and not down at your feet.", author: "Stephen Hawking"),
        Quote(text: "If I have seen further it is by standing on the shoulders of Giants.", author: "Isaac Newton"),
        Quote(text: "Science progresses best when observations force us to alter our preconceptions.", author: "Vera Rubin"),
        Quote(text: "Life need not be easy, provided only that it is not empty.", author: "Lise Meitner"),
        Quote(text: "The good thing about science is that it's true whether or not you believe in it.", author: "Neil deGrasse Tyson"),
        Quote(text: "Never be limited by other people's limited imaginations.", author: "Mae Jemison"),
    ]

    /// Days since a fixed start, so each day gets the next quote and animation.
    static var day: Int { Calendar.current.dateComponents([.day], from: Date(timeIntervalSince1970: 0), to: Date()).day ?? 0 }
    static var quote: Quote { quotes[day % quotes.count] }

    // MARK: Animations: (time in seconds, columns, rows) -> lines of text, drawn to fill whatever space they get.

    struct Animation { let name: String; let frame: (Double, Int, Int) -> [String] }

    static let animations: [Animation] = [
        Animation(name: "rain", frame: rain),
        Animation(name: "waves", frame: waves),
        Animation(name: "stars", frame: stars),
        Animation(name: "vinyl", frame: vinyl),
        Animation(name: "levels", frame: levels),
        Animation(name: "sunrise", frame: sunrise),
        Animation(name: "bounce", frame: bounce),
        Animation(name: "fire", frame: fire),
        Animation(name: "dancer", frame: dancer),
        Animation(name: "code", frame: code),
    ]

    // A different order of animations from the quotes, so the same pair doesn't come round together.
    static var animation: Animation { animations[(day * 7 + 3) % animations.count] }

    /// A repeatable pseudo-random number in 0..<1 for (a, b).
    static func noise(_ a: Int, _ b: Int) -> Double {
        var h = UInt64(bitPattern: Int64(a &* 73_856_093 ^ b &* 19_349_663 ^ day &* 83_492_791))
        h ^= h >> 33; h = h &* 0xff51afd7ed558ccd; h ^= h >> 33
        return Double(h % 10_000) / 10_000
    }

    /// A character grid that ignores writes outside it.
    struct Grid {
        let w: Int, h: Int
        var cells: [[Character]]
        init(_ w: Int, _ h: Int) { self.w = max(1, w); self.h = max(1, h); cells = Array(repeating: Array(repeating: " ", count: self.w), count: self.h) }
        subscript(x: Int, y: Int) -> Character {
            get { x >= 0 && x < w && y >= 0 && y < h ? cells[y][x] : " " }
            set { if x >= 0 && x < w && y >= 0 && y < h { cells[y][x] = newValue } }
        }
        mutating func write(_ text: String, x: Int, y: Int) { for (i, c) in text.enumerated() where c != " " { self[x + i, y] = c } }
        var lines: [String] { cells.map { String($0) } }
    }

    static func rain(_ t: Double, _ w: Int, _ h: Int) -> [String] {
        var g = Grid(w, h); let step = Int(t * 12), fall = h + 8
        for x in 0..<w where noise(x, 0) < 0.45 {
            let speed = 1 + Int(noise(x, 1) * 2), y = (step * speed / 2 + Int(noise(x, 2) * Double(fall))) % fall
            g[x, y] = "|"; g[x, y - 1] = "'"; g[x, y - 2] = "'"
        }
        for x in 0..<w where noise(x, step / 3) < 0.12 { if g[x, h - 1] == " " { g[x, h - 1] = "." } }
        return g.lines
    }

    static func waves(_ t: Double, _ w: Int, _ h: Int) -> [String] {
        var g = Grid(w, h); let H = Double(h)
        for x in 0..<w {
            let X = Double(x)
            let level = H * 0.45 + H * 0.2 * sin(X * 0.09 - t * 1.6) + H * 0.08 * sin(X * 0.23 + t * 1.1)
            let top = Int(level.rounded())
            g[x, top] = "~"
            for y in (top + 1)..<max(top + 1, h) { g[x, y] = y == top + 1 ? "≈" : (y - top < 4 ? "░" : "·") }
        }
        return g.lines
    }

    static func stars(_ t: Double, _ w: Int, _ h: Int) -> [String] {
        var g = Grid(w, h); let step = Int(t * 4)
        for i in 0..<max(16, w * h / 35) {
            let x = Int(noise(i, 10) * Double(w)), y = Int(noise(i, 11) * Double(h))
            g[x, y] = ["·", "·", "+", "*", "✦", "*", "+", " "][(step + Int(noise(i, 12) * 8)) % 8]
        }
        // A shooting star now and then, across from the top right.
        let run = step % 40
        if run < 20 { for k in 0..<4 { g[w - 1 - (run * 4) + k * 2, run / 2 + 1 - k / 2] = k == 0 ? "*" : "-" } }
        return g.lines
    }

    /// Distance from (cx, cy) in rows, counting a column as half a row (characters are about twice as tall as wide).
    static func dist(_ x: Int, _ y: Int, _ cx: Double, _ cy: Double) -> (d: Double, angle: Double) {
        let dx = (Double(x) - cx) / 2, dy = Double(y) - cy
        return ((dx * dx + dy * dy).squareRoot(), atan2(dy, dx))
    }

    static func vinyl(_ t: Double, _ w: Int, _ h: Int) -> [String] {
        var g = Grid(w, h); let r = Double(h) * 0.46, cx = Double(w) * 0.3, cy = Double(h) / 2 - 0.5
        let spin = (t * 3.5).truncatingRemainder(dividingBy: 2 * .pi)
        for y in 0..<h {
            for x in 0..<w {
                let (d, a) = dist(x, y, cx, cy)
                guard d <= r else { continue }
                var diff = abs(a - spin + .pi).truncatingRemainder(dividingBy: 2 * .pi) - .pi
                diff = abs(diff)
                if d < r * 0.12 { g[x, y] = "o" }
                else if d < r * 0.32 { g[x, y] = "@" }
                else if diff < 0.12 { g[x, y] = "/" }
                else { g[x, y] = Int(d * 1.3) % 2 == 0 ? ":" : "." }
            }
        }
        // Notes drifting up and to the right.
        for i in 0..<8 {
            let life = (t * 0.6 + noise(i, 40) * 5).truncatingRemainder(dividingBy: 5) / 5
            g[Int(cx + r * 2.2 + Double(i) * Double(w) * 0.06 + life * 10), Int(Double(h) * (0.85 - life * 0.8))] = i % 2 == 0 ? "♪" : "♫"
        }
        return g.lines
    }

    static func levels(_ t: Double, _ w: Int, _ h: Int) -> [String] {
        var g = Grid(w, h)
        let beat = pow(max(0, sin(t * 2 * .pi * 2)), 6)
        for x in stride(from: 0, to: w, by: 3) {
            let v = 0.15 + 0.4 * abs(sin(t * (1.2 + noise(x, 20) * 3) + Double(x) * 0.3)) + 0.45 * beat * (1 - Double(x) / Double(w))
            let top = h - Int((v * Double(h)).rounded())
            for y in max(0, top)..<h { g[x, y] = "█"; g[x + 1, y] = "█" }
            g[x, top - 2] = "▁"; g[x + 1, top - 2] = "▁" // peak marker
        }
        return g.lines
    }

    static func sunrise(_ t: Double, _ w: Int, _ h: Int) -> [String] {
        var g = Grid(w, h)
        let cycle = t.truncatingRemainder(dividingBy: 20) / 20, r = Double(h) * 0.22
        let cx = Double(w) / 2, cy = Double(h) - 1 - sin(cycle * .pi) * Double(h) * 0.6
        let turn = t * 0.4
        for y in 0..<(h - 1) {
            for x in 0..<w {
                let (d, a) = dist(x, y, cx, cy)
                if d <= r { g[x, y] = d > r - 1 ? "o" : "@"; continue }
                // Rays: 12 spokes, turning slowly, out to twice the sun's size.
                let spoke = (a - turn) * 6 / .pi
                if d < r * 2.4 && abs(spoke - spoke.rounded()) < 0.08 { g[x, y] = "·" }
            }
        }
        for x in 0..<w { g[x, h - 1] = "_" }
        return g.lines
    }

    static func bounce(_ t: Double, _ w: Int, _ h: Int) -> [String] {
        var g = Grid(w, h)
        for x in 0..<w { g[x, h - 1] = "▔" }
        for i in 0..<3 {
            let span = Double(w - 1), speed = 7 + Double(i) * 3
            let p = (t * speed + Double(i) * span * 0.6).truncatingRemainder(dividingBy: span * 2)
            let x = Int(p < span ? p : span * 2 - p)
            let y = h - 2 - Int(abs(sin(t * (2.2 + Double(i) * 0.7))) * Double(h - 2))
            g[x, y] = "o"; g[x - 1, y] = g[x - 1, y] == " " ? "·" : g[x - 1, y]
            if y >= h - 2 { g[x, h - 1] = "^" }
        }
        return g.lines
    }

    static func fire(_ t: Double, _ w: Int, _ h: Int) -> [String] {
        var g = Grid(w, h); let step = Int(t * 12)
        let ramp: [Character] = [" ", ".", ":", "*", "s", "S", "#", "$"]
        for y in 0..<h {
            for x in 0..<w {
                let heat = 1 - Double(h - 1 - y) / Double(h) // hotter at the bottom
                let flames = 0.55 + 0.45 * sin(Double(x) * 0.12 + sin(t * 0.7) * 2) // several flames across
                let v = heat * heat * flames * 1.5 + (noise(x + step * 31, y + step) - 0.5) * 0.5
                g[x, y] = ramp[max(0, min(ramp.count - 1, Int(v * Double(ramp.count))))]
            }
        }
        return g.lines
    }

    static func dancer(_ t: Double, _ w: Int, _ h: Int) -> [String] {
        var g = Grid(w, h)
        let poses = [
            [" \\o/ ", "  |  ", " / \\ "],
            [" _o_ ", "  |  ", " | | "],
            ["  o/ ", " /|  ", " / > "],
            [" \\o  ", "  |\\ ", " < \\ "],
        ]
        let beat = Int(t * 3)
        for (n, x) in stride(from: 2, to: w - 5, by: 13).enumerated() {
            let pose = poses[(beat + n * 3) % poses.count]
            for row in 0..<3 { g.write(pose[row], x: x, y: h - 4 + row) }
        }
        for x in 0..<w { g[x, h - 1] = (x + beat) % 2 == 0 ? "~" : "=" }
        for i in 0..<max(6, w / 8) {
            let life = (t * 0.5 + noise(i, 50) * 4).truncatingRemainder(dividingBy: 4) / 4
            g[Int(noise(i, 51) * Double(w)), Int(Double(h - 5) * (1 - life))] = i % 2 == 0 ? "♪" : "♫"
        }
        return g.lines
    }

    static func code(_ t: Double, _ w: Int, _ h: Int) -> [String] {
        var g = Grid(w, h); let step = Int(t * 9), trail = max(3, h / 3)
        for x in stride(from: 0, to: w, by: 2) {
            let head = (step + Int(noise(x, 30) * Double(h * 2))) % (h + trail + 6)
            for y in 0..<h where y <= head && head - y < trail { g[x, y] = noise(x * 7 + y, step) < 0.5 ? "0" : "1" }
        }
        return g.lines
    }
}

/// Today's animation filling the space behind the open notch, very faint, about 8 frames a second.
struct DailyBackdrop: View {
    private static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let cell = CGSize(width: ("M" as NSString).size(withAttributes: [.font: font]).width,
                                     height: NSLayoutManager().defaultLineHeight(for: font))

    var body: some View {
        GeometryReader { geo in
            let cols = Int(geo.size.width / Self.cell.width), rows = Int(geo.size.height / Self.cell.height)
            TimelineView(.animation(minimumInterval: 1 / 8)) { context in
                Text(Daily.animation.frame(context.date.timeIntervalSinceReferenceDate, cols, rows).joined(separator: "\n"))
                    .font(Font(Self.font))
                    .foregroundStyle(.white.opacity(0.07))
                    .fixedSize()
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Today's quote and who said it.
struct DailyQuote: View {
    var compact = false
    var body: some View {
        let q = Daily.quote
        VStack(alignment: .leading, spacing: 4) {
            Text(q.text).font(.system(size: compact ? 12 : 13, weight: .semibold)).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            Text("— \(q.author)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
        }
    }
}

/// The quote (the animation runs behind the whole open notch).
struct DailyCard: View {
    var body: some View { DailyQuote(compact: true).frame(maxWidth: .infinity, alignment: .leading) }
}
