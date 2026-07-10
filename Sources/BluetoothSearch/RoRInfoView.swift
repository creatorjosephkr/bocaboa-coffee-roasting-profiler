import SwiftUI
struct RoRInfoView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("RoR (Rate of Rise) 란?")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.textPrimary)
            
            Text("RoR은 원두 투입 후 1분 시점 부터 1분 단위로 온도가 얼마나 상승했는지를 나타내는 '온도 상승률'입니다. 로스팅 과정을 제어하고 향미 발현을 예측하는 가장 핵심적인 지표입니다.")
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .lineSpacing(4)
            
            VStack {
                if let path = Bundle.main.path(forResource: "ror_chart", ofType: "png"),
                   let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 280)
                } else {
                    Text("그래프 이미지를 불러올 수 없습니다.")
                        .foregroundColor(.red)
                        .frame(height: 200)
                }
            }
            .padding(15)
            .background(Color.appSurface2)
            .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("💡 핵심 체크 포인트")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("• 점진적 하락 (Constantly Declining RoR): 이상적인 로스팅은 터닝 포인트(최하점) 이후 RoR이 시간이 지남에 따라 완만하게 하락해야 합니다.")
                    Text("• 크래쉬 (Crash): 1차 팝핑 부근에서 수분이 빠져나가며 온도가 덜 오르는 현상으로 RoR이 급격히 떨어지는 것입니다. 베이크드(Baked) 향미의 원인이 될 수 있습니다.")
                    Text("• 플릭 (Flick): 로스팅 후반부에 열을 주체하지 못하고 RoR이 다시 상승하는 현상입니다. 거친 탄 맛을 유발할 수 있습니다.")
                }
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .lineSpacing(3)
            }
            .padding(15)
            .background(Color.appSurface2)
            .cornerRadius(12)
            
            HStack {
                Spacer()
                Button("확인") { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    .controlSize(.large)
            }
        }
        .padding(30)
        .frame(width: 700)
        .background(Color.appSurface)
        .cornerRadius(16)
        .shadow(radius: 20)
    }
}
