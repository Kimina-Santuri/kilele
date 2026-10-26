import SwiftUI

/// Something new each day: a proverb (traditional, so free to use; mostly Swahili and other African ones) and a small
/// ASCII animation, both picked by the date, so they change at midnight and stay the same all day.
enum Daily {
    struct Quote { let text: String; let translation: String; let origin: String }

    static let quotes: [Quote] = [
        Quote(text: "Haba na haba hujaza kibaba.", translation: "Little by little fills the measure.", origin: "Swahili"),
        Quote(text: "Pole pole ndio mwendo.", translation: "Slowly, slowly is the way to go.", origin: "Swahili"),
        Quote(text: "Kidole kimoja hakivunji chawa.", translation: "One finger can't crush a louse.", origin: "Swahili"),
        Quote(text: "Usipoziba ufa utajenga ukuta.", translation: "Fix the crack, or you'll rebuild the wall.", origin: "Swahili"),
        Quote(text: "Mvumilivu hula mbivu.", translation: "The patient one eats the ripe fruit.", origin: "Swahili"),
        Quote(text: "Asiyefunzwa na mamaye hufunzwa na ulimwengu.", translation: "Who isn't taught by their mother is taught by the world.", origin: "Swahili"),
        Quote(text: "Bandu bandu huisha gogo.", translation: "Chip by chip, the log is finished.", origin: "Swahili"),
        Quote(text: "Fimbo ya mbali haiui nyoka.", translation: "A stick far away doesn't kill the snake.", origin: "Swahili"),
        Quote(text: "Penye nia pana njia.", translation: "Where there's a will there's a way.", origin: "Swahili"),
        Quote(text: "Akili ni nywele, kila mtu ana zake.", translation: "Wisdom is like hair: everyone has their own.", origin: "Swahili"),
        Quote(text: "Mchumia juani hulia kivulini.", translation: "Who works in the sun eats in the shade.", origin: "Swahili"),
        Quote(text: "Dalili ya mvua ni mawingu.", translation: "Clouds are the sign of rain.", origin: "Swahili"),
        Quote(text: "Maji yakimwagika hayazoleki.", translation: "Spilt water can't be gathered.", origin: "Swahili"),
        Quote(text: "Kila ndege huruka kwa ubawa wake.", translation: "Every bird flies with its own wings.", origin: "Swahili"),
        Quote(text: "Usiache mbachao kwa msala upitao.", translation: "Don't drop your old mat for a passing prayer rug.", origin: "Swahili"),
        Quote(text: "Ukiona vyaelea, vimeundwa.", translation: "If you see it floating, someone built it.", origin: "Swahili"),
        Quote(text: "Mwenda pole hajikwai.", translation: "Who walks slowly doesn't stumble.", origin: "Swahili"),
        Quote(text: "Heri kujikwaa kidole kuliko kujikwaa ulimi.", translation: "Better to stub a toe than trip on your tongue.", origin: "Swahili"),
        Quote(text: "Wapiganapo tembo nyasi huumia.", translation: "When elephants fight, the grass suffers.", origin: "Swahili"),
        Quote(text: "Chovya chovya humaliza buyu la asali.", translation: "Dip by dip empties the gourd of honey.", origin: "Swahili"),
        Quote(text: "Ngoma ivumayo haidumu.", translation: "The drum that booms loudest doesn't last.", origin: "Swahili"),
        Quote(text: "Mtaka cha mvunguni sharti ainame.", translation: "Who wants what's under the bed must bend down.", origin: "Swahili"),
        Quote(text: "Umoja ni nguvu, utengano ni udhaifu.", translation: "Unity is strength, division is weakness.", origin: "Swahili"),
        Quote(text: "Siku njema huonekana asubuhi.", translation: "A good day shows itself in the morning.", origin: "Swahili"),
        Quote(text: "If you want to go fast, go alone. If you want to go far, go together.", translation: "", origin: "African proverb"),
        Quote(text: "A river cuts through rock not because of its power, but its persistence.", translation: "", origin: "Proverb"),
        Quote(text: "However long the night, the dawn will break.", translation: "", origin: "African proverb"),
        Quote(text: "The best time to plant a tree was twenty years ago. The second best time is now.", translation: "", origin: "Proverb"),
        Quote(text: "When the music changes, so does the dance.", translation: "", origin: "Hausa proverb"),
        Quote(text: "Smooth seas do not make skilful sailors.", translation: "", origin: "African proverb"),
        Quote(text: "No one tests the depth of a river with both feet.", translation: "", origin: "Ashanti proverb"),
        Quote(text: "The child who is not embraced by the village will burn it down to feel its warmth.", translation: "", origin: "African proverb"),
        Quote(text: "Until the lion learns to write, tales of the hunt will glorify the hunter.", translation: "", origin: "African proverb"),
        Quote(text: "A single bracelet does not jingle.", translation: "", origin: "Congolese proverb"),
        Quote(text: "Rain does not fall on one roof alone.", translation: "", origin: "Cameroonian proverb"),
        Quote(text: "He who learns, teaches.", translation: "", origin: "Ethiopian proverb"),
        Quote(text: "Wood already touched by fire is not hard to set alight.", translation: "", origin: "Ashanti proverb"),
        Quote(text: "Even the best cooking pot will not produce food.", translation: "", origin: "African proverb"),
        Quote(text: "The fool speaks, the wise listen.", translation: "", origin: "Ethiopian proverb"),
        Quote(text: "Where you will sit when you are old shows where you stood in youth.", translation: "", origin: "Yoruba proverb"),
        Quote(text: "Move your neck according to the music.", translation: "", origin: "Ethiopian proverb"),
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

/// Today's proverb, with its translation and where it's from.
struct DailyQuote: View {
    var compact = false
    var body: some View {
        let q = Daily.quote
        VStack(alignment: .leading, spacing: 3) {
            Text(q.text).font(.system(size: compact ? 12 : 13, weight: .semibold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            if !q.translation.isEmpty { Text(q.translation).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(2) }
            Text("— \(q.origin)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }
    }
}

/// The proverb with the animation beside it.
struct DailyCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DailyQuote(compact: true).frame(maxWidth: .infinity, alignment: .leading)
            DailyAnimation()
        }
    }
}
