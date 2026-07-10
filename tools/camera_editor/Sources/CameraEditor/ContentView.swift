import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var editingRow: SpeedPatchRow?
    @State private var showingAddSheet = false
    @State private var showingWriteBackSheet = false

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
        .sheet(isPresented: $showingWriteBackSheet) {
            WriteBackSheet(model: model)
        }
    }

    // MARK: Sidebar — carga desde el ZIP + búsqueda

    private var sidebar: some View {
        Form {
            Section("1. ZIP de mapas") {
                Text("Ruta habitual: \(AppModel.examplePath)")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Text(model.zipPath.isEmpty ? "(sin seleccionar)" : (model.zipPath as NSString).lastPathComponent)
                        .font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Elegir ZIP…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.zip]
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url {
                            model.loadZip(path: url.path)
                        }
                    }
                }

                if !model.availableCountries.isEmpty {
                    Picker("País", selection: $model.selectedCountry) {
                        ForEach(model.availableCountries, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                    Button {
                        model.extractAndLoadFromZip()
                    } label: {
                        Label("Extraer y cargar", systemImage: "archivebox")
                    }
                    .disabled(model.isLoading)
                    Text("Se extrae a \(model.cacheDir) — solo la primera vez, luego queda cacheado.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                if model.isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            if !model.writableDBPath.isEmpty {
                Section("Guardar cambios") {
                    Text("Copia editable:\n\(model.writableDBPath)")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        showingWriteBackSheet = true
                    } label: {
                        Label("Reinyectar en el ZIP…", systemImage: "square.and.arrow.down.on.square")
                    }
                }
            }

            Section("2. Buscar") {
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
        .frame(minWidth: 360)
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
            .padding([.horizontal, .top])

            if !model.streetNames.isEmpty {
                Text("⚠️ Columna \"Calle\" = candidato por proximidad de posición en el .haftlt, no un enlace LINK_ID↔nombre confirmado (ver docs/haftlt_build_diff_260128.md).")
                    .font(.caption2).foregroundStyle(.orange)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            Table(model.rows) {
                TableColumn("Calle (candidata)") { row in
                    Text(streetNameCandidate(for: row) ?? "—")
                        .foregroundStyle(streetNameCandidate(for: row) == nil ? .secondary : .primary)
                }
                TableColumn("LINK_ID") { row in Text("\(row.linkId)").monospaced() }
                TableColumn("DIR") { row in Text(dirLabel(row.dir)) }
                TableColumn("SP_LIMIT") { row in Text("\(row.spLimit) km/h") }
                TableColumn("VEHICLE_TYPE") { row in Text(row.vehicleType.map { "\($0)" } ?? "—") }
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

    private func streetNameCandidate(for row: SpeedPatchRow) -> String? {
        guard let lid = UInt32(exactly: row.linkId) else { return nil }
        return model.candidateStreetName(for: lid)
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
            if model.store?.hasVehicleType ?? true {
                TextField("VEHICLE_TYPE", text: $vehicleType)
            } else {
                Text("Esta build de SPEED_PATCH.db no tiene columna VEHICLE_TYPE (build ≥ 260128).")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button(existing == nil ? "Añadir" : "Guardar") {
                    guard let lid = Int64(linkId), let sp = Int(spLimit) else { return }
                    let hasVT = model.store?.hasVehicleType ?? true
                    let vt: Int? = hasVT ? (Int(vehicleType) ?? 0) : nil
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
                vehicleType = e.vehicleType.map { "\($0)" } ?? "0"
            }
        }
    }
}

private struct WriteBackSheet: View {
    @ObservedObject var model: AppModel
    @State private var destPath: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reinyectar SPEED_PATCH.db en el ZIP").font(.headline)
            Text("Esta operación actualiza la entrada SPEED_PATCH.db dentro del ZIP de destino. Por defecto se propone una **copia nueva** del ZIP (no el original) — puede tardar varios minutos la primera vez por el tamaño (~18 GB). Elige el original solo si sabes lo que haces.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                TextField("ZIP de destino", text: $destPath)
                Button("Elegir…") {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.zip]
                    panel.nameFieldStringValue = ((model.zipPath as NSString).lastPathComponent as NSString).deletingPathExtension + "_editado.zip"
                    if panel.runModal() == .OK, let url = panel.url {
                        destPath = url.path
                    }
                }
            }

            Text("⚠️ Tras esto sigue haciendo falta recalcular MD5 y CRC32 en Rio_MY22_EU.ver antes de instalar — ver .claude/memory/speed_patch_workflow.md. Este botón NO hace esa parte.")
                .font(.caption2).foregroundStyle(.orange)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Reinyectar") {
                    model.writeBackToZip(destinationZip: destPath.isEmpty ? model.zipPath : destPath)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(destPath.isEmpty)
            }
        }
        .padding()
        .frame(width: 460)
        .onAppear {
            let dir = (model.zipPath as NSString).deletingLastPathComponent
            let base = ((model.zipPath as NSString).lastPathComponent as NSString).deletingPathExtension
            destPath = dir + "/" + base + "_editado.zip"
        }
    }
}
