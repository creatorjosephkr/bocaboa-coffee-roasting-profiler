import SwiftUI

struct DTRInfoView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("DTR (Development Time Ratio) 란?")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.textPrimary)
            
            Text("전체 로스팅 시간 중 1차 크랙(팝핑) 이후부터 배출까지의 '디벨롭 시간(Development Time)'이 차지하는 비율(%)입니다. 커피의 향미 특성과 로스팅 포인트를 결정하는 중요한 기준이 됩니다.")
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .lineSpacing(4)
            
            VStack(spacing: 15) {
                GeometryReader { geo in
                    let totalWidth = geo.size.width
                    let devWidth = totalWidth * 0.2 // 20% DTR example
                    
                    VStack(spacing: 8) {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.orange.opacity(0.8))
                                .frame(width: totalWidth - devWidth)
                            Rectangle()
                                .fill(Color.brown.opacity(0.9))
                                .frame(width: devWidth)
                        }
                        .frame(height: 36)
                        .cornerRadius(8)
                        
                        HStack(spacing: 0) {
                            Text("건조 & 마이야르 (80%)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.orange)
                                .frame(width: totalWidth - devWidth)
                            
                            Text("디벨롭 (DTR 20%)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.brown)
                                .frame(width: devWidth)
                        }
                    }
                }
                .frame(height: 60)
            }
            .padding(15)
            .background(Color.appSurface2)
            .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("💡 DTR에 따른 로스팅 가이드")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text("• ~ 14%:").bold().frame(width: 70, alignment: .leading)
                        Text("라이트 로스트 (산미 강조, 꽃향이나 과일 같은 뉘앙스)")
                    }
                    HStack(alignment: .top) {
                        Text("• 15 ~ 18%:").bold().frame(width: 70, alignment: .leading)
                        Text("미디엄 로스트 (산미와 단맛의 균형적인 밸런스)")
                    }
                    HStack(alignment: .top) {
                        Text("• 19 ~ 22%:").bold().frame(width: 70, alignment: .leading)
                        Text("미디엄 다크 로스트 (산미 감소, 단맛과 바디감 강조)")
                    }
                    HStack(alignment: .top) {
                        Text("• 23% ~:").bold().frame(width: 70, alignment: .leading)
                        Text("다크 로스트 (로스팅 캐릭터 중심, 쌉쌀하고 묵직한 스모키)")
                    }
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
