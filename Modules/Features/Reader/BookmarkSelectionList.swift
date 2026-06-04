import SwiftUI
import UIKit

/// 書籤／重點清單的「清單本體」，以 UIKit `UITableView` 實作（非 SwiftUI `List`）。
///
/// 之所以用 UIKit：純 SwiftUI `List` 無法開啟 iOS 原生的「兩指拖曳多選」手勢
/// （`tableView(_:shouldBeginMultipleSelectionInteractionAt:)`）。這裡開啟該手勢，
/// 並完全自繪選取樣式（灰色勾選圓圈＋灰底圓角列），不使用 SwiftUI 的 `EditMode`。
///
/// 編輯狀態與選取集合由外層 SwiftUI 以 binding 持有，工具列的 checklist→xmark 按鈕、
/// 底部「已選取 N 個」與垃圾桶都在 SwiftUI 層；本元件只負責清單與選取手勢。
struct BookmarkSelectionList: UIViewControllerRepresentable {
    var items: [Bookmark]
    @Binding var isEditing: Bool
    @Binding var selection: Set<UUID>
    var primaryText: (Bookmark) -> String
    var primaryLines: Int
    var dateText: (Bookmark) -> String
    var pageText: (Bookmark) -> String?
    var onSelect: (Bookmark) -> Void
    var onDelete: (Bookmark) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UITableViewController {
        let tvc = UITableViewController(style: .plain)
        tvc.clearsSelectionOnViewWillAppear = false
        let table = tvc.tableView!
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.allowsMultipleSelectionDuringEditing = true
        table.register(BookmarkListCell.self, forCellReuseIdentifier: BookmarkListCell.reuseID)
        table.separatorInset = UIEdgeInsets(top: 0, left: DSSpacing.lg, bottom: 0, right: DSSpacing.lg)
        table.backgroundColor = .clear
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 64
        context.coordinator.table = table
        return tvc
    }

    func updateUIViewController(_ tvc: UITableViewController, context: Context) {
        let coord = context.coordinator
        coord.parent = self
        let table = tvc.tableView!

        if coord.items.map(\.id) != items.map(\.id) {
            coord.items = items
            table.reloadData()
        } else {
            coord.items = items
        }

        if table.isEditing != isEditing {
            table.setEditing(isEditing, animated: true)
        }
        coord.reconcileSelection(selection)
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var parent: BookmarkSelectionList
        var items: [Bookmark]
        weak var table: UITableView?

        init(_ parent: BookmarkSelectionList) {
            self.parent = parent
            self.items = parent.items
        }

        /// 把表格目前選取狀態對齊到 binding（處理 SwiftUI 端的程式化清空，例如切換分頁或刪除後）。
        func reconcileSelection(_ desired: Set<UUID>) {
            guard let table else { return }
            let currentlySelected = table.indexPathsForSelectedRows ?? []
            for ip in currentlySelected where ip.row < items.count {
                if !desired.contains(items[ip.row].id) {
                    table.deselectRow(at: ip, animated: false)
                }
            }
            for (row, bm) in items.enumerated() where desired.contains(bm.id) {
                let ip = IndexPath(row: row, section: 0)
                if !(table.indexPathsForSelectedRows ?? []).contains(ip) {
                    table.selectRow(at: ip, animated: false, scrollPosition: .none)
                }
            }
        }

        private func setSelected(_ id: UUID, _ selected: Bool) {
            var updated = parent.selection
            if selected { updated.insert(id) } else { updated.remove(id) }
            parent.selection = updated
        }

        // MARK: DataSource

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            items.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: BookmarkListCell.reuseID, for: indexPath) as! BookmarkListCell
            let bm = items[indexPath.row]
            cell.configure(
                primary: parent.primaryText(bm),
                primaryLines: parent.primaryLines,
                date: parent.dateText(bm),
                page: parent.pageText(bm)
            )
            return cell
        }

        // MARK: Delegate — selection

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            let bm = items[indexPath.row]
            if tableView.isEditing {
                setSelected(bm.id, true)
            } else {
                tableView.deselectRow(at: indexPath, animated: false)
                parent.onSelect(bm)
            }
        }

        func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
            guard tableView.isEditing, indexPath.row < items.count else { return }
            setSelected(items[indexPath.row].id, false)
        }

        // MARK: Delegate — two-finger drag multi-select (the whole point of going UIKit)

        func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
            true
        }

        func tableView(_ tableView: UITableView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
            // 兩指拖曳會自動進入選取模式；同步回 SwiftUI 讓工具列/底部列跟著切換。
            if !parent.isEditing { parent.isEditing = true }
        }

        // MARK: Delegate — swipe to delete (non-editing)

        func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard indexPath.row < items.count else { return nil }
            let bm = items[indexPath.row]
            let delete = UIContextualAction(style: .destructive, title: localized("刪除")) { [weak self] _, _, done in
                self?.parent.onDelete(bm)
                done(true)
            }
            delete.image = UIImage(systemName: "trash")
            return UISwipeActionsConfiguration(actions: [delete])
        }
    }
}

// MARK: - Cell

/// 自繪列：主標題＋日期（次行）＋頁碼（靠右）。選取樣式為灰色勾選圓圈＋整列灰底圓角，
/// 對齊圖 3。多選圓圈的顏色由 `tintColor` 決定（灰色），灰底由 `multipleSelectionBackgroundView` 提供。
final class BookmarkListCell: UITableViewCell {
    static let reuseID = "BookmarkListCell"

    private let primaryLabel = UILabel()
    private let dateLabel = UILabel()
    private let pageLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        // 選取圓圈用灰色（而非系統預設藍），對齊圖 3。
        tintColor = .systemGray

        primaryLabel.font = .preferredFont(forTextStyle: .body)
        primaryLabel.textColor = .label
        primaryLabel.adjustsFontForContentSizeCategory = true

        dateLabel.font = .preferredFont(forTextStyle: .footnote)
        dateLabel.textColor = .secondaryLabel
        dateLabel.adjustsFontForContentSizeCategory = true

        pageLabel.font = .preferredFont(forTextStyle: .subheadline)
        pageLabel.textColor = .secondaryLabel
        pageLabel.adjustsFontForContentSizeCategory = true
        pageLabel.setContentHuggingPriority(.required, for: .horizontal)
        pageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [primaryLabel, dateLabel])
        textStack.axis = .vertical
        textStack.spacing = DSSpacing.xs

        let rowStack = UIStackView(arrangedSubviews: [textStack, pageLabel])
        rowStack.axis = .horizontal
        rowStack.alignment = .firstBaseline
        rowStack.spacing = DSSpacing.sm
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DSSpacing.md),
            rowStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -DSSpacing.md)
        ])

        // 選取時的整列灰底圓角（內縮 8pt，圓角 12pt）。
        let pill = UIView()
        pill.backgroundColor = .systemGray5
        pill.layer.cornerRadius = DSRadius.lg
        pill.layer.cornerCurve = .continuous
        pill.translatesAutoresizingMaskIntoConstraints = false
        let pillContainer = UIView()
        pillContainer.backgroundColor = .clear
        pillContainer.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: pillContainer.leadingAnchor, constant: DSSpacing.sm),
            pill.trailingAnchor.constraint(equalTo: pillContainer.trailingAnchor, constant: -DSSpacing.sm),
            pill.topAnchor.constraint(equalTo: pillContainer.topAnchor, constant: 2),
            pill.bottomAnchor.constraint(equalTo: pillContainer.bottomAnchor, constant: -2)
        ])
        multipleSelectionBackgroundView = pillContainer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func configure(primary: String, primaryLines: Int, date: String, page: String?) {
        primaryLabel.numberOfLines = primaryLines
        primaryLabel.text = primary
        dateLabel.text = date
        pageLabel.text = page
        pageLabel.isHidden = (page == nil)
    }
}
