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

    // MARK: Animations: (time in seconds) -> lines of text, 24 wide by 5 tall.

    struct Animation { let name: String; let frame: (Double) -> [String] }

    static let width = 24, height = 5

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

    static func blank() -> [[Character]] { Array(repeating: Array(repeating: " ", count: width), count: height) }
    static func lines(_ grid: [[Character]]) -> [String] { grid.map { String($0) } }

    static func rain(_ t: Double) -> [String] {
        var g = blank(), step = Int(t * 10)
        for x in 0..<width where noise(x, 0) < 0.55 {
            let speed = 1 + Int(noise(x, 1) * 2), y = (step * speed / 2 + Int(noise(x, 2) * 9)) % (height + 3)
            if y < height { g[y][x] = "|" }
            if y - 1 >= 0 && y - 1 < height { g[y - 1][x] = "'" }
        }
        for x in 0..<width where noise(x, step / 3) < 0.15 { g[height - 1][x] = g[height - 1][x] == " " ? "." : g[height - 1][x] }
        return lines(g)
    }

    static func waves(_ t: Double) -> [String] {
        var g = blank()
        for x in 0..<width {
            let h = 2 + 1.6 * sin(Double(x) * 0.45 - t * 2.4) + 0.6 * sin(Double(x) * 0.9 + t * 1.3)
            let top = max(0, min(height - 1, height - 1 - Int(h.rounded())))
            g[top][x] = "~"
            for y in (top + 1)..<height { g[y][x] = y == top + 1 ? "≈" : "░" }
        }
        return lines(g)
    }

    static func stars(_ t: Double) -> [String] {
        var g = blank(), step = Int(t * 4)
        for i in 0..<16 {
            let x = Int(noise(i, 10) * Double(width)), y = Int(noise(i, 11) * Double(height))
            let phase = (step + Int(noise(i, 12) * 8)) % 8
            g[y][x] = ["·", "·", "+", "*", "✦", "*", "+", " "][phase]
        }
        let shoot = (step / 2) % 16
        if shoot < 8 { let x = width - 1 - shoot * 3, y = shoot / 3; if x >= 0 && y < height { g[y][x] = "*"; if x + 1 < width { g[y][x + 1] = "-" } } }
        return lines(g)
    }

    static func vinyl(_ t: Double) -> [String] {
        let marks = ["|", "/", "-", "\\"], m = marks[Int(t * 8) % 4]
        let notes = ["♪  ", " ♫ ", "  ♪", " ♫ "][Int(t * 2) % 4]
        return [
            "     .-\"\"\"\"-.          ",
            "   /  .--.   \\    \(notes)  ",
            "  |  ( \(m)  )  |  ~~~~~~ ",
            "   \\  '--'   /         ",
            "     '-....-'          ",
        ].map { String($0.prefix(width)).padding(toLength: width, withPad: " ", startingAt: 0) }
    }

    static func levels(_ t: Double) -> [String] {
        var g = blank()
        for x in stride(from: 0, to: width, by: 2) {
            let beat = pow(max(0, sin(t * 2 * .pi * 2)), 6)
            let v = 0.25 + 0.35 * abs(sin(t * (1.5 + noise(x, 20) * 3) + Double(x))) + 0.4 * beat * (1 - Double(x) / Double(width))
            let h = Int((v * Double(height)).rounded())
            for y in 0..<height where height - y <= h { g[y][x] = "█" }
        }
        return lines(g)
    }

    static func sunrise(_ t: Double) -> [String] {
        let cycle = t.truncatingRemainder(dividingBy: 12) / 12, rise = Int(sin(cycle * .pi) * 3.2)
        var g = blank()
        let cx = width / 2, cy = height - 1 - rise
        let rays: [(Int, Int, Character)] = [(-5, 0, "-"), (5, 0, "-"), (-3, -1, "\\"), (3, -1, "/"), (0, -2, "|")]
        for (dx, dy, c) in rays where Int(t * 3) % 2 == 0 || dy == 0 {
            let x = cx + dx, y = cy + dy
            if y >= 0 && y < height - 1 && x >= 0 && x < width { g[y][x] = c }
        }
        for dx in -2...2 { let y = cy; if y >= 0 && y < height - 1 { g[y][cx + dx] = abs(dx) == 2 ? "(" : "@" } }
        if cy >= 0 && cy < height - 1 { g[cy][cx + 2] = ")" }
        for x in 0..<width { g[height - 1][x] = "_" }
        return lines(g)
    }

    static func bounce(_ t: Double) -> [String] {
        var g = blank()
        let span = Double(width - 1), p = (t * 6).truncatingRemainder(dividingBy: span * 2)
        let x = Int(p < span ? p : span * 2 - p)
        let y = height - 2 - Int(abs(sin(t * 3.2)) * Double(height - 2))
        g[max(0, y)][x] = "o"
        for i in 0..<width { g[height - 1][i] = "▔" }
        if y >= height - 2 { g[height - 1][x] = "^" }
        return lines(g)
    }

    static func fire(_ t: Double) -> [String] {
        var g = blank(), step = Int(t * 12)
        let ramp: [Character] = [" ", ".", ":", "*", "s", "S", "#", "$"]
        for y in 0..<height {
            for x in 0..<width {
                let base = 1 - Double(height - 1 - y) / Double(height) // hotter at the bottom
                let centre = 1 - abs(Double(x) - Double(width) / 2) / (Double(width) / 2)
                let v = base * centre * 1.4 + (noise(x + step * 31, y + step) - 0.5) * 0.6
                g[y][x] = ramp[max(0, min(ramp.count - 1, Int(v * Double(ramp.count))))]
            }
        }
        return lines(g)
    }

    static func dancer(_ t: Double) -> [String] {
        let poses = [
            [" \\o/ ", "  |  ", " / \\ "],
            [" _o_ ", "  |  ", " | | "],
            ["  o/ ", " /|  ", " / > "],
            [" \\o  ", "  |\\ ", " < \\ "],
        ]
        let p = poses[Int(t * 3) % poses.count], q = poses[(Int(t * 3) + 2) % poses.count]
        let floor = Int(t * 6) % 2 == 0 ? "~=~=~=~=~=~=~=~=~=~=~=~=" : "=~=~=~=~=~=~=~=~=~=~=~=~"
        return ["       ♪          ♫     "] + (0..<3).map { "  " + p[$0] + "          " + q[$0] + "  " } + [floor]
    }

    static func code(_ t: Double) -> [String] {
        var g = blank(), step = Int(t * 9)
        for x in stride(from: 0, to: width, by: 2) {
            let head = (step + Int(noise(x, 30) * 20)) % (height + 4)
            for y in 0..<height where y <= head && head - y < 3 {
                g[y][x] = noise(x * 7 + y, step) < 0.5 ? "0" : "1"
            }
        }
        return lines(g)
    }
}

/// Today's animation, about 8 frames a second.
struct DailyAnimation: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 8)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Text(Daily.animation.frame(t).joined(separator: "\n"))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineSpacing(-1)
                .fixedSize()
        }
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

/// The quote with the animation beside it.
struct DailyCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DailyQuote(compact: true).frame(maxWidth: .infinity, alignment: .leading)
            DailyAnimation()
        }
    }
}
