import SwiftUI

struct SourceSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Source scenes").font(.headline)
                Spacer()
                Picker("Source", selection: $model.selectedSourceID) {
                    ForEach(SourceCatalogue.descriptors) { source in
                        Text(source.name).tag(source.id)
                    }
                }
                .frame(width: 220)
            }
            if let index = model.sourceConfigurations.firstIndex(where: { $0.id == model.selectedSourceID }) {
                Toggle("Enable source", isOn: $model.sourceConfigurations[index].enabled)
                if model.selectedSourceID == "outlook" || model.selectedSourceID == "slack" {
                    let kind = model.selectedSourceID == "outlook" ? "newEmail" : "directMessage"
                    Picker("Message cue", selection: Binding(
                        get: { model.sourceConfigurations[index].cuePatternIDs[kind] ?? model.patterns[0].id },
                        set: { model.sourceConfigurations[index].cuePatternIDs[kind] = $0 }
                    )) {
                        ForEach(model.patterns) { pattern in
                            Text(pattern.name).tag(pattern.id)
                        }
                    }
                }
                ForEach(model.sourceConfigurations[index].layers.indices, id: \.self) { layerIndex in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("Ambient", isOn: $model.sourceConfigurations[index].layers[layerIndex].enabled)
                            Picker("Pattern", selection: $model.sourceConfigurations[index].layers[layerIndex].patternID) {
                                ForEach(model.patterns) { pattern in
                                    Text(pattern.name).tag(pattern.id)
                                }
                            }
                            Slider(value: $model.sourceConfigurations[index].layers[layerIndex].strength, in: 0...1)
                                .frame(width: 120)
                            Button("Remove") { model.removeLayer(sourceIndex: index, layerIndex: layerIndex) }
                        }
                        ForEach(model.sourceConfigurations[index].layers[layerIndex].mappings.indices, id: \.self) { mappingIndex in
                            mappingRow(sourceIndex: index, layerIndex: layerIndex, mappingIndex: mappingIndex)
                        }
                        Button("Add Mapping") { model.addMapping(sourceIndex: index, layerIndex: layerIndex) }
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    Button("Add Ambient Layer") { model.addLayer(sourceIndex: index) }
                    Button("Save Source Settings") { model.saveSourceSettings() }
                    if model.selectedSourceID == "sample" {
                        Slider(value: $model.sampleLevel, in: 0...1)
                            .frame(width: 130)
                            .onChange(of: model.sampleLevel) { _, _ in model.updateSampleLevel() }
                        Button("Play Sample") { model.playSampleSource() }
                    }
                }
            }
        }
    }

    private func mappingRow(sourceIndex: Int, layerIndex: Int, mappingIndex: Int) -> some View {
        let source = SourceCatalogue.descriptors.first(where: { $0.id == model.selectedSourceID })
        let mapping = $model.sourceConfigurations[sourceIndex].layers[layerIndex].mappings[mappingIndex]
        return HStack {
            Picker("Value", selection: mapping.valueName) {
                ForEach(source?.valueNames ?? [], id: \.self) { Text($0).tag($0) }
            }
            Picker("Controls", selection: mapping.control) {
                ForEach(PatternControl.allCases) { Text($0.rawValue).tag($0) }
            }
            Text("Input")
            TextField("Low", value: mapping.inputMin, format: .number)
                .frame(width: 52)
            Text("to")
            TextField("High", value: mapping.inputMax, format: .number)
                .frame(width: 52)
            Text("Output")
            TextField("Low", value: mapping.outputMin, format: .number)
                .frame(width: 52)
            Text("to")
            TextField("High", value: mapping.outputMax, format: .number)
                .frame(width: 52)
            Button("×") { model.removeMapping(sourceIndex: sourceIndex, layerIndex: layerIndex, mappingIndex: mappingIndex) }
        }
        .textFieldStyle(.roundedBorder)
    }
}
