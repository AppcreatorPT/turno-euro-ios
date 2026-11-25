import SwiftUI

@main struct TurnoEuro: App {
    @StateObject private var shift = Shift()
    var body: some Scene {
        WindowGroup { Dashboard().environmentObject(shift) }
    }
}

struct Dashboard: View {
    @EnvironmentObject private var shift: Shift
    @AppStorage("reserve") private var reserveText = "21,3"
    @AppStorage("fuelPerKm") private var fuelText = ""
    @AppStorage("targetHourly") private var goalText = "15"
    @State private var demo = false
    @State private var showSettings = false
    @FocusState private var keyboard: Bool

    private func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
    private var limits: Limits? {
        guard let reserve = number(reserveText), (0...100).contains(reserve),
              let goal = number(goalText), goal.isFinite, goal > 0 else { return nil }
        let fuel = number(fuelText)
        if !fuelText.isEmpty && !(fuel.map { $0.isFinite && $0 >= 0 } ?? false) { return nil }
        return Limits(reserve: reserve, fuel: fuel, goal: goal)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(shift.status, systemImage: shift.phase == .active ? "waveform" : "pause.circle")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    if shift.phase == .idle {
                        Button("Iniciar turno") {
                            if let limits { Task { await shift.start(limits) } }
                        }.disabled(limits == nil)
                    } else {
                        Button("Terminar turno", role: .destructive) { Task { await shift.stop() } }
                            .disabled(shift.phase == .stopping)
                    }
                    if let note = shift.alertNote { Text(note) }
                } footer: {
                    Text("Durante o turno, o iPhone lê as ofertas e apresenta uma faixa. As imagens ficam apenas em memória.")
                }
                if let last = shift.latest {
                    Section("Última avaliação") {
                        Text(last.title).font(.headline)
                        Text(last.body)
                    }
                }
                Section("Critérios do turno") {
                    DisclosureGroup(isExpanded: $showSettings) {
                        field("Meta após custos (€/h)", $goalText)
                        field("Reserva sobre a faturação (%)", $reserveText)
                        field("Gasóleo estimado (€/km)", $fuelText)
                        Text("A reserva inicial de 21,3% é provisória. Para estimar o gasóleo por km, multiplica os litros por 100 km pelo preço por litro e divide por 100. Deixa vazio até teres uma estimativa.")
                            .font(.footnote)
                    } label: { Text("Meta e custos") }
                    .disabled(shift.phase != .idle)
                    if limits == nil { Text("Revê os valores da meta, da reserva e do gasóleo.").foregroundStyle(.red) }
                }
                Section {
                    Button("Mostrar oferta de teste") { demo = true }
                        .disabled(shift.phase != .active)
                    if let elapsed = shift.testTime { Text(elapsed) }
                } footer: {
                    Text("Para o teste, inicia um turno e escolhe o ecrã completo. Depois abre a oferta fictícia.")
                }
            }
            .navigationTitle("Turno Euro")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Concluir") { keyboard = false }
                }
            }
            .sheet(isPresented: $demo, onDismiss: { shift.endTest() }) {
                VStack(alignment: .leading, spacing: 18) {
                    Spacer()
                    Text("Oferta fictícia").font(.subheadline)
                    Text("Livraison").font(.title3)
                    Text("6,40 €").font(.largeTitle.bold())
                    Text("20 min (4 km)").font(.title2)
                    Text("Accepter").font(.headline)
                    Divider()
                    Text(shift.testTime ?? "A aguardar leitura do ecrã…")
                    Button("Fechar teste") { demo = false }.buttonStyle(.borderedProminent)
                    Spacer()
                }.padding(28).onAppear { shift.beginTest() }
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.subheadline)
            TextField(label, text: text).keyboardType(.decimalPad).focused($keyboard)
                .textFieldStyle(.roundedBorder).accessibilityLabel(label)
        }.padding(.vertical, 4)
    }
}
