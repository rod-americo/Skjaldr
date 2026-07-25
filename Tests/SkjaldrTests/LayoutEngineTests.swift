import CoreGraphics
import Foundation
import Testing
@testable import SkjaldrApp

@Suite("Motor de layout")
struct LayoutEngineTests {
    private let engine = LayoutEngine()

    @Test("Automático posiciona vinte imagens sem sobreposição")
    func automaticLayoutContainsEveryItemWithoutOverlap() {
        let items = (0..<20).map {
            LayoutEngine.Input(
                id: UUID(),
                aspectRatio: [0.55, 0.8, 1.0, 1.5, 2.2][$0 % 5],
                isPrimary: false
            )
        }
        let result = engine.calculate(
            items: items,
            mode: .automatic,
            canvasWidth: 1800,
            margin: 32,
            horizontalSpacing: 16,
            verticalSpacing: 16
        )

        #expect(result.placements.count == items.count)
        #expect(result.size.width == 1800)
        #expect(result.size.height > 0)
        for placement in result.placements {
            #expect(placement.frame.width > 0)
            #expect(placement.frame.height > 0)
            #expect(placement.frame.minX >= 31)
            #expect(placement.frame.maxX <= 1769)
        }
        assertNoOverlap(result.placements)
    }

    @Test("Grade aceita mistura de orientações")
    func gridSupportsMixtureOfOrientations() {
        let items = [
            LayoutEngine.Input(id: UUID(), aspectRatio: 2.0, isPrimary: false),
            LayoutEngine.Input(id: UUID(), aspectRatio: 0.5, isPrimary: false),
            LayoutEngine.Input(id: UUID(), aspectRatio: 1.0, isPrimary: false),
            LayoutEngine.Input(id: UUID(), aspectRatio: 1.7, isPrimary: false),
            LayoutEngine.Input(id: UUID(), aspectRatio: 0.7, isPrimary: false)
        ]
        let result = engine.calculate(
            items: items,
            mode: .grid,
            canvasWidth: 1200,
            margin: 20,
            horizontalSpacing: 10,
            verticalSpacing: 10
        )
        #expect(result.placements.count == 5)
        assertNoOverlap(result.placements)
    }

    @Test("Comparação organiza as imagens em pares")
    func comparisonCreatesPairs() {
        let items = (0..<5).map {
            LayoutEngine.Input(id: UUID(), aspectRatio: 1.5 + Double($0) / 10, isPrimary: false)
        }
        let result = engine.calculate(
            items: items,
            mode: .comparison,
            canvasWidth: 1600,
            margin: 40,
            horizontalSpacing: 20,
            verticalSpacing: 20
        )
        #expect(result.placements.count == 5)
        #expect(abs(result.placements[0].frame.midY - result.placements[1].frame.midY) <= 0.5)
        #expect(abs(result.placements[2].frame.midY - result.placements[3].frame.midY) <= 0.5)
        assertNoOverlap(result.placements)
    }

    @Test("Imagem principal recebe área maior")
    func primaryImageReceivesLargerArea() {
        let primaryID = UUID()
        let items = [
            LayoutEngine.Input(id: primaryID, aspectRatio: 1.4, isPrimary: true),
            LayoutEngine.Input(id: UUID(), aspectRatio: 1.4, isPrimary: false),
            LayoutEngine.Input(id: UUID(), aspectRatio: 1.4, isPrimary: false)
        ]
        let result = engine.calculate(
            items: items,
            mode: .automatic,
            canvasWidth: 1800,
            margin: 32,
            horizontalSpacing: 16,
            verticalSpacing: 16
        )
        let primaryArea = result.placements.first(where: { $0.itemID == primaryID })!.frame.area
        let secondaryAreas = result.placements
            .filter { $0.itemID != primaryID }
            .map { $0.frame.area }
        #expect(secondaryAreas.allSatisfy { primaryArea > $0 })
    }

    @Test("Recalcula cem imagens abaixo da meta de 150 ms")
    func layoutPerformance() {
        let items = (0..<100).map {
            LayoutEngine.Input(
                id: UUID(),
                aspectRatio: [0.55, 0.8, 1.0, 1.5, 2.2][$0 % 5],
                isPrimary: false
            )
        }
        let clock = ContinuousClock()
        let start = clock.now
        let result = engine.calculate(
            items: items,
            mode: .automatic,
            canvasWidth: 1800,
            margin: 32,
            horizontalSpacing: 16,
            verticalSpacing: 16
        )
        let elapsed = start.duration(to: clock.now)

        #expect(result.placements.count == 100)
        #expect(elapsed < .milliseconds(150))
    }

    private func assertNoOverlap(_ placements: [LayoutPlacement]) {
        for first in placements.indices {
            for second in placements.indices where second > first {
                let intersection = placements[first].frame.intersection(placements[second].frame)
                #expect(intersection.isNull || intersection.width < 1 || intersection.height < 1)
            }
        }
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
