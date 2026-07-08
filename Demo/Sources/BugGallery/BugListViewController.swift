#if DEBUG
import UIKit

/// Home screen of the bug reproduction gallery: one row per confirmed SDK bug. Tapping a row
/// pushes a dedicated screen that reproduces it in isolation with its own `SecureFieldsManager`
/// and mock network responses.
final class BugListViewController: UITableViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Galerie de bugs SecureFields"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Démo classique",
            style: .plain,
            target: self,
            action: #selector(openClassicDemo)
        )
    }

    @objc private func openClassicDemo() {
        navigationController?.pushViewController(DemoViewController(), animated: true)
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        BugCatalog.all.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "10 cas de reproduction confirmés — voir chaque écran pour les étapes détaillées et le comportement attendu vs observé."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let bug = BugCatalog.all[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = "Bug #\(bug.number) — \(bug.title)"
        content.secondaryText = bug.subtitle
        content.secondaryTextProperties.numberOfLines = 2
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let bug = BugCatalog.all[indexPath.row]
        navigationController?.pushViewController(bug.makeViewController(), animated: true)
    }
}
#endif
