import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var editingRow: SpeedPatchRow?
    @State private var showingAddSheet = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(item: $editingRow) { row in
            EditSheet(model: model, existing: row)
        }
        .sheet(isPresented: $showingAddSheet) {
            EditSheet(model: model, existing: nil)
        }
    }

    // MARK: Sidebar — carga de ficheros + búsqueda

    private var sidebar: some View {
        Form {
            Section("Ficheros") {
                FilePickerRow(title: ".haftlt (p.ej. VIT_EUR_SPN.haftlt)", path: $model.haftltPath) { path in
                    model.loadHaftlt(path: path)
                }
                FilePickerRow(title: "SPEED_PATCH.db original", path: $model.speedPatchOriginalPath) { path in
                    model.loadSpeedPatch(originalPath: path)
                }
                if !model.writableDBPath.isEmpty {
                    Text("Copia editable:\n\(model.writableDBPath)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Modo de búsqueda") {
                Picker("", selection: $model.searchMode) {
                    ForEach(SearchMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: model.searchMode) { _, _ in model.page = 0; model.refresh() }

                switch model.searchMode {
                case .browseAll:
                    Text("Lista completa de SPEED_PATCH.db, paginada.")
                        .font(.caption).foregroundStyle(.secondary)
                case .byLinkId:
                    TextField("LINK_ID exacto", text: $model.linkIdQuery)
                        .onSubmit { model.page = 0; model.refresh() }
                    Button("Buscar") { model.page = 0; model.refresh() }
                case .byStreet:
                    TextField("Nombre de calle contiene…", text: $model.streetQuery)
                        .onChange(of: model.streetQuery) { _, _ in
                            model.updateStreetMatches()
                            model.page = 0
                            model.refresh()
                        }
                    Text("⚠️ La conexión nombre de calle ↔ LINK_ID no está confirmada (ver docs/haftlt_build_diff_260128.md). Esto muestra candidatos por proximidad de posición en el fichero — no un enlace verificado.")
                        .font(.caption2).foregroundStyle(.orange)
                    if !model.streetMatches.isEmpty {
                        List(model.streetMatches) { s in
                            Text(s.text).font(.caption)
                        }
                        .frame(height: 160)
                    }
                }
            }

            if !model.statusMessage.isEmpty {
                Section {
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(model.statusIsError ? .red : .green)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 340)
    }

    // MARK: Detalle — tabla SPEED_PATCH + acciones

    private var detail: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SPEED_PATCH.db — \(model.rows.count) filas mostradas" + (model.searchMode == .browseAll ? " de \(model.totalCount)" : ""))
                    .font(.headline)
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Añadir", systemImage: "plus")
                }
                .disabled(model.store == nil)
            }
            .padding()

            Table(model.rows) {
                TableColumn("LINK_ID") { row in Text("\(row.linkId)").monospaced() }
                TableColumn("DIR") { row in Text(dirLabel(row.dir)) }
                TableColumn("SP_LIMIT") { row in Text("\(row.spLimit) km/h") }
                TableColumn("VEHICLE_TYPE") { row in Text("\(row.vehicleType)") }
                TableColumn("") { row in
                    HStack {
                        Button("Editar") { editingRow = row }
                        Button("Borrar", role: .destructive) { model.delete(row: row) }
                    }
                }
            }

            if model.searchMode == .browseAll {
                HStack {
                    Button("← Anterior") { model.prevPage() }.disabled(model.page == 0)
                    Text("Página \(model.page + 1) de \(max(1, (model.totalCount + model.pageSize - 1) / model.pageSize))")
                        .font(.caption)
                    Button("Siguiente →") { model.nextPage() }
                        .disabled((model.page + 1) * model.pageSize >= model.totalCount)
                }
                .padding(8)
            }
        }
    }

    private func dirLabel(_ d: Int) -> String {
        switch d {
        case 0: return "0 (A→B)"
        case 1: return "1 (B→A)"
        case 2: return "2 (ambos)"
        default: return "\(d)"
        }
    }
}

private struct FilePickerRow: View {
    let title: String
    @Binding var path: String
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(path.isEmpty ? "(sin seleccionar)" : (path as NSString).lastPathComponent)
                    .font(.caption).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Elegir…") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    if panel.runModal() == .OK, let url = panel.url {
                        path = url.path
                        onPick(url.path)
                    }
                }
            }
        }
    }
}

private struct EditSheet: View {
    @ObservedObject var model: AppModel
    let existing: SpeedPatchRow?

    @State private var linkId: String = ""
    @State private var dir: Int = 2
    @State private var spLimit: String = "50"
    @State private var vehicleType: String = "0"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("LINK_ID", text: $linkId)
                .disabled(existing != nil)
            Picker("DIR", selection: $dir) {
                Text("0 (A→B)").tag(0)
                Text("1 (B→A)").tag(1)
                Text("2 (ambos)").tag(2)
            }
            TextField("SP_LIMIT (km/h)", text: $spLimit)
            TextField("VEHICLE_TYPE", text: $vehicleType)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button(existing == nil ? "Añadir" : "Guardar") {
                    guard let lid = Int64(linkId), let sp = Int(spLimit), let vt = Int(vehicleType) else { return }
                    model.save(linkId: lid, dir: dir, spLimit: sp, vehicleType: vt)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 340)
        .onAppear {
            if let e = existing {
                linkId = "\(e.linkId)"
                dir = e.dir
                spLimit = "\(e.spLimit)"
                vehicleType = "\(e.vehicleType)"
            }
        }
    }
}
