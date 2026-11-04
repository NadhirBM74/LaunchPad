import Foundation
import CoreGraphics

// MARK: - Élément Positionné sur la Grille d'Emplacements

struct PlacedItem: Identifiable, Equatable {
    let item: LayoutItem
    let page: Int
    let col: Int
    let row: Int
    let colSpan: Int
    let rowSpan: Int
    let center: CGPoint
    let frameSize: CGSize
    let index: Int

    var id: String { item.id }
    var isWidget: Bool { item.isWidget }

    /// Vérifie si l'élément couvre la case (c, r) sur sa page
    func occupies(c: Int, r: Int) -> Bool {
        c >= col && c < (col + colSpan) && r >= row && r < (row + rowSpan)
    }

    /// Liste de tous les emplacements de grille occupés par cet élément
    var occupiedSlots: [(col: Int, row: Int)] {
        var slots: [(col: Int, row: Int)] = []
        for r in row..<(row + rowSpan) {
            for c in col..<(col + colSpan) {
                slots.append((c, r))
            }
        }
        return slots
    }

    static func == (lhs: PlacedItem, rhs: PlacedItem) -> Bool {
        lhs.item == rhs.item &&
        lhs.page == rhs.page &&
        lhs.col == rhs.col &&
        lhs.row == rhs.row &&
        lhs.colSpan == rhs.colSpan &&
        lhs.rowSpan == rhs.rowSpan &&
        lhs.center == rhs.center &&
        lhs.frameSize == rhs.frameSize &&
        lhs.index == rhs.index
    }
}

// MARK: - Moteur de Disposition de Grille Partagée (Launchpad Style)

struct GridLayoutEngine {

    /// Calcule la disposition complète de tous les éléments (applications et widgets)
    /// sur une grille partagée sans aucun chevauchement.
    /// Un widget petit occupe 1 emplacement (1x1), un moyen occupe 2 emplacements (2x1), etc.
    static func computeLayout(
        items: [LayoutItem],
        columns: Int,
        rows: Int,
        metrics: GridMetrics
    ) -> [PlacedItem] {
        let cols = max(1, columns)
        let rws = max(1, rows)
        let totalSlots = cols * rws
        var placed: [PlacedItem] = []
        placed.reserveCapacity(items.count)

        var currentPage = 0
        // Matrice plate des cases occupées pour la page courante: pageOccupied[row * cols + col]
        var pageOccupied = [Bool](repeating: false, count: totalSlots)
        var globalIndex = 0

        for item in items {
            let (spanCols, spanRows) = item.span(columns: cols, rows: rws)
            var placedOnPage = false

            while !placedOnPage {
                if let pos = findSlot(colSpan: spanCols, rowSpan: spanRows, in: pageOccupied, columns: cols, rows: rws) {
                    // Réserve tous les emplacements de la grille couverts par cet élément
                    for r in pos.row..<(pos.row + spanRows) {
                        let rowOffset = r * cols + pos.col
                        for dc in 0..<spanCols {
                            pageOccupied[rowOffset + dc] = true
                        }
                    }

                    // Calcul précis des coordonnées graphiques et du centre
                    let slotX = metrics.horizontalPadding + CGFloat(pos.col) * metrics.cellWidth
                    let slotY = CGFloat(pos.row) * metrics.cellHeight
                    let boxWidth = CGFloat(spanCols) * metrics.cellWidth
                    let boxHeight = CGFloat(spanRows) * metrics.cellHeight
                    let center = CGPoint(x: slotX + boxWidth / 2.0, y: slotY + boxHeight / 2.0)

                    let frameSize = item.isWidget
                        ? CGSize(width: max(40, boxWidth - 14), height: max(40, boxHeight - 14))
                        : CGSize(width: metrics.cellWidth, height: metrics.tileHeight)

                    let entry = PlacedItem(
                        item: item,
                        page: currentPage,
                        col: pos.col,
                        row: pos.row,
                        colSpan: spanCols,
                        rowSpan: spanRows,
                        center: center,
                        frameSize: frameSize,
                        index: globalIndex
                    )
                    placed.append(entry)
                    globalIndex += 1
                    placedOnPage = true
                } else {
                    // L'élément ne rentre pas sur la page courante -> passage à la page suivante (réinitialisation sans allocation)
                    currentPage += 1
                    pageOccupied.withUnsafeMutableBufferPointer { $0.initialize(repeating: false) }
                }
            }
        }

        return placed
    }

    /// Recherche le premier emplacement libre sur une page respectant les dimensions demandées
    private static func findSlot(
        colSpan: Int,
        rowSpan: Int,
        in grid: [Bool],
        columns: Int,
        rows: Int
    ) -> (col: Int, row: Int)? {
        guard colSpan <= columns && rowSpan <= rows else { return nil }

        for r in 0...(rows - rowSpan) {
            for c in 0...(columns - colSpan) {
                var canFit = true
                for dr in 0..<rowSpan {
                    let rOffset = (r + dr) * columns + c
                    for dc in 0..<colSpan {
                        if grid[rOffset + dc] {
                            canFit = false
                            break
                        }
                    }
                    if !canFit { break }
                }
                if canFit {
                    return (c, r)
                }
            }
        }
        return nil
    }

    /// Retourne le numéro de page attribué à chaque élément selon la grille (sans nécessiter de GridMetrics).
    static func pageAssignments(
        items: [LayoutItem],
        columns: Int,
        rows: Int
    ) -> [Int] {
        let cols = max(1, columns)
        let rws = max(1, rows)
        let totalSlots = cols * rws
        var pages: [Int] = []
        pages.reserveCapacity(items.count)

        var currentPage = 0
        var pageOccupied = [Bool](repeating: false, count: totalSlots)

        for item in items {
            let (spanCols, spanRows) = item.span(columns: cols, rows: rws)
            let safeCols = min(spanCols, cols)
            let safeRows = min(spanRows, rws)
            var placed = false

            while !placed {
                if let pos = findSlot(colSpan: safeCols, rowSpan: safeRows, in: pageOccupied, columns: cols, rows: rws) {
                    for r in pos.row..<(pos.row + safeRows) {
                        let rowOffset = r * cols + pos.col
                        for dc in 0..<safeCols {
                            pageOccupied[rowOffset + dc] = true
                        }
                    }
                    pages.append(currentPage)
                    placed = true
                } else {
                    currentPage += 1
                    pageOccupied.withUnsafeMutableBufferPointer { $0.initialize(repeating: false) }
                }
            }
        }

        return pages
    }

    /// Vérifie si une liste d'éléments peut être positionnée sur la grille sans dépasser les limites
    static func canLayout(
        items: [LayoutItem],
        columns: Int,
        rows: Int,
        maxPages: Int = 30
    ) -> Bool {
        let cols = max(1, columns)
        let rws = max(1, rows)
        let totalSlots = cols * rws

        // Chaque élément doit au minimum pouvoir entrer sur une page vide
        for item in items {
            let (cSpan, rSpan) = item.span(columns: cols, rows: rws)
            if cSpan > cols || rSpan > rws {
                return false
            }
        }

        var currentPage = 0
        var pageOccupied = [Bool](repeating: false, count: totalSlots)

        for item in items {
            let (spanCols, spanRows) = item.span(columns: cols, rows: rws)
            var placed = false

            while !placed {
                if currentPage >= maxPages { return false }
                if let pos = findSlot(colSpan: spanCols, rowSpan: spanRows, in: pageOccupied, columns: cols, rows: rws) {
                    for r in pos.row..<(pos.row + spanRows) {
                        let rowOffset = r * cols + pos.col
                        for dc in 0..<spanCols {
                            pageOccupied[rowOffset + dc] = true
                        }
                    }
                    placed = true
                } else {
                    currentPage += 1
                    pageOccupied.withUnsafeMutableBufferPointer { $0.initialize(repeating: false) }
                }
            }
        }

        return true
    }
}
