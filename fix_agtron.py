import sys

content = open("Sources/BluetoothSearch/ContentView.swift").read()

start_str = "                    // 아그트론 색상 예측 패널"
end_str = "                    // 화력/풍량 컨트롤 패널 (블루투스 연결 시)"

start_idx = content.find(start_str)
end_idx = content.find(end_str)

new_agtron = """                    // 아그트론 색상 예측 패널
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "paintpalette.fill")
                                .foregroundColor(.brown)
                            Text("아그트론 색상 예측 (목표치)")
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                            Text("\\(currentAgtronValue)")
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                .foregroundColor(.brown)
                        }
                        
                        let detail = currentAgtronDetail
                        HStack {
                            Text(detail.range)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.brown.opacity(0.1))
                                .foregroundColor(.brown)
                                .cornerRadius(4)
                            Text(detail.common)
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text(detail.sca)
                                .font(.system(size: 10))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .padding(12)
                    .background(Color.appSurface)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                    .padding(.horizontal, 16)

"""

new_content = content[:start_idx] + new_agtron + content[end_idx:]

with open("Sources/BluetoothSearch/ContentView.swift", "w") as f:
    f.write(new_content)

