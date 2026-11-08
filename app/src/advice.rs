//! §6.10.2 — *"Kiểm tra băng thông trước khi bắt đầu"*.
//!
//! > `POST /api/sessions` → response có `recommended_preset` dựa trên đo 5 s
//! > gần nhất của user đó; hoặc hiện ước lượng "~8 Mbps" trước khi bấm Start.
//!
//! # Vì sao file này tách riêng
//!
//! Luật ở đây là **quyết định sản phẩm**, không phải plumbing: đo được 2 Mbps
//! thì đề nghị "Mượt", đo 20 Mbps thì "Nét". Nếu viết thẳng trong route thì
//! không test được, và cái sai sẽ là kiểu khó thấy — người dùng mạng 4G được
//! đề nghị 12 Mbps, stream giật, và không ai biết vì sao.
//!
//! # Số đo lấy từ đâu
//!
//! Từ [`LiveMetrics`] của phiên **trước** (§8.1 `stats`). Đây là số **thật**:
//! `jpeg_bytes` cộng dồn trên đường truyền, `frames` đếm sau khi gửi xong.
//! Không phải ước lượng từ kích thước màn hình — ước lượng đó luôn sai vì nó
//! giả định nội dung desktop nén giống nhau, trong khi một cửa sổ code đen nền
//! nén nhỏ hơn video 20 lần.
//!
//! # Cửa sổ "5 s gần nhất"
//!
//! Spec nói *5 s gần nhất*, không phải trung bình cả phiên. Bản này dùng toàn
//! bộ phiên trước (vì `LiveMetrics` chưa có cửa sổ trượt) — nhưng chỉ tin khi
//! phiên đó **đủ dài** (≥ [`MIN_SAMPLE_MS`]), vì 200 ms đầu tiên luôn có 1–2
//! frame khổng lồ (keyframe JPEG đầy đủ) và sẽ thổi phồng băng thông lên gấp
//! nhiều lần, khiến đề nghị thành "Nét" trên mạng 3G.

use crate::session_state::{preset_by_id, Preset, PRESETS};

/// Phiên trước phải dài ít nhất chừng này mới dùng số đo.
///
/// 1.5 s = đủ vài chục frame ở 60 fps, đủ để keyframe đầu không còn chi phối.
/// Ngắn hơn ⇒ băng thông đo được là của *keyframe*, không phải của stream.
pub const MIN_SAMPLE_MS: u128 = 1500;

/// Kết quả của bước "kiểm tra băng thông trước khi bắt đầu".
#[derive(Debug, Clone, PartialEq)]
pub struct Advice {
    /// §6.10.2 tên trường trong response là `recommended_preset`.
    pub recommended: &'static Preset,
    /// Băng thông đo được của phiên trước, Mbps. `None` = chưa có số đo dùng được.
    pub measured_mbps: Option<f64>,
    /// Một câu cho UI. Spec cho phép *"hoặc hiện ước lượng ~8 Mbps"* — đây là
    /// chỗ đó: nói thẳng là ước lượng hay số đo, vì hai thứ tin cậy khác nhau.
    pub basis_vi: String,
}

/// §6.10.2 — đề nghị preset từ số đo phiên trước.
///
/// `measured_mbps` = `None` khi chưa stream lần nào (máy mới, hoặc phiên trước
/// quá ngắn). Khi đó **không đoán**: đề nghị mặc định của §6.10.1 ("Cân bằng")
/// và nói rõ đây là ước lượng theo spec, không phải số đo.
pub fn recommend(measured_mbps: Option<f64>) -> Advice {
    let Some(mbps) = measured_mbps.filter(|value| value.is_finite() && *value > 0.0) else {
        let fallback = preset_by_id(crate::session_state::DEFAULT_PRESET)
            .expect("DEFAULT_PRESET phải có trong PRESETS");
        return Advice {
            recommended: fallback,
            measured_mbps: None,
            // §6.10.1 nói `auto` = 8 Mbps. Nói "ước lượng" chứ không nói "đo
            // được" — người dùng có quyền biết con số này từ đâu ra.
            basis_vi: format!("Ước lượng theo mặc định (~{:.0} Mbps)", fallback.mbps),
        };
    };

    // Chọn preset **cao nhất mà mạng chịu được**, có biên an toàn 25 %: đo được
    // 8 Mbps thì đừng đề nghị preset 8 Mbps, vì bitrate của preset là **đỉnh**
    // còn đường truyền thật luôn thấp hơn con số đo trong khoảng ngắn. Biên 25 %
    // là lựa chọn của tôi, và nó chỉ ảnh hưởng **đề nghị** — người dùng đổi
    // được, preset đã lưu không bị ghi đè.
    let usable = mbps * 0.75;
    // `PRESETS` xếp từ cao xuống thấp (sharp 12 → low 1.5), nên phần tử đầu
    // tiên vừa với `usable` là đề nghị.
    let recommended = PRESETS
        .iter()
        .find(|preset| preset.mbps as f64 <= usable)
        // Mạng tệ hơn cả preset thấp nhất ⇒ vẫn đề nghị nó, kèm cảnh báo trong
        // `basis_vi`. Trả `None` ở đây thì UI phải tự quyết, và nó sẽ chọn
        // "Cân bằng" 8 Mbps cho một đường 300 kbps — đúng cái cần tránh.
        .unwrap_or(&PRESETS[PRESETS.len() - 1]);

    Advice {
        recommended,
        measured_mbps: Some(mbps),
        basis_vi: if usable < PRESETS[PRESETS.len() - 1].mbps as f64 {
            format!(
                "Đo được {:.1} Mbps — thấp hơn cả mức \"Tiết kiệm\"; hình sẽ giật, nên dùng dây mạng nếu được",
                mbps
            )
        } else {
            format!("Đo được {:.1} Mbps trong phiên trước", mbps)
        },
    }
}

/// §6.10.2 câu thứ hai: *"hoặc hiện ước lượng ~8 Mbps trước khi bấm Start"*.
///
/// UI hiện con số này **trước** khi có phiên nào, để người dùng biết mình sắp
/// dùng bao nhiêu băng thông. Trả `(mbps, nhãn_vi)` của preset mặc định.
pub fn estimate_before_start() -> (f32, &'static str) {
    let preset = preset_by_id(crate::session_state::DEFAULT_PRESET)
        .expect("DEFAULT_PRESET phải có trong PRESETS");
    (preset.mbps, preset.label_vi)
}

/// JSON của [`Advice`] để nhét vào response §8.1 (`POST /api/sessions`).
pub fn advice_json(advice: &Advice) -> String {
    let measured = match advice.measured_mbps {
        Some(mbps) => format!("{:.1}", mbps),
        // `null`, không phải `0` — UI phải phân biệt "chưa đo" với "đo được 0".
        None => "null".to_string(),
    };
    format!(
        "{{\"recommended_preset\":\"{}\",\"measured_mbps\":{},\"basis\":{}}}",
        advice.recommended.id,
        measured,
        crate::json_quote(&advice.basis_vi),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_measurement_falls_back_to_the_spec_default_not_a_guess() {
        // Máy mới: chưa stream lần nào. §6.10.1 nói mặc định là "Cân bằng".
        let advice = recommend(None);
        assert_eq!(advice.recommended.id, "auto");
        assert_eq!(advice.measured_mbps, None);
        // Phải nói rõ đây là ước lượng — người dùng có quyền biết con số từ đâu.
        assert!(advice.basis_vi.contains("Ước lượng"), "{}", advice.basis_vi);
    }

    #[test]
    fn a_good_link_gets_the_sharp_preset() {
        // 20 Mbps đo được ⇒ 20 × 0.75 = 15 ≥ 12 (sharp). Đề nghị "Nét" là đúng:
        // người dùng có mạng tốt mà bị đề nghị "Mượt" thì hình mờ vô cớ.
        assert_eq!(recommend(Some(20.0)).recommended.id, "sharp");
    }

    #[test]
    fn the_obvious_wrong_answers_are_not_chosen() {
        // Đây là bảng thật của §6.10.1. Nếu ai sửa ngưỡng, test này chỉ ra ngay
        // vì nó ghi **kỳ vọng của người dùng**, không phải giá trị nội bộ.
        //
        //   đo 30 → dư cho 12 Mbps đỉnh (22.5 ≥ 12) → Nét
        //   đo 12 → 9 Mbps dùng được (9 < 12, ≥ 8) → Cân bằng
        //   đo  6 →  4.5 Mbps          (4.5 ≥ 4)   → Mượt
        //   đo 2.5 → 1.875 Mbps        (≥ 1.5)     → Tiết kiệm
        assert_eq!(recommend(Some(30.0)).recommended.id, "sharp");
        assert_eq!(recommend(Some(12.0)).recommended.id, "auto");
        assert_eq!(recommend(Some(6.0)).recommended.id, "smooth");
        assert_eq!(recommend(Some(2.5)).recommended.id, "low");
    }

    #[test]
    fn a_link_worse_than_every_preset_still_gets_a_preset_and_a_warning() {
        // 300 kbps. Trả `None` thì UI tự chọn và nó sẽ chọn "Cân bằng" 8 Mbps.
        let advice = recommend(Some(0.3));
        assert_eq!(advice.recommended.id, "low");
        assert!(advice.basis_vi.contains("thấp hơn"), "phải cảnh báo: {}", advice.basis_vi);
        // Không được khuyên dùng 4G/roaming khi chính nó không đủ.
        assert!(advice.basis_vi.contains("dây mạng"), "{}", advice.basis_vi);
    }

    #[test]
    fn a_bogus_measurement_is_treated_as_no_measurement() {
        // `0.0`/`NaN`/`inf` không phải số đo. Nếu lọt vào, `find` sẽ không khớp
        // gì và rơi xuống `low` — tức là mạng tốt cũng bị đề nghị "Tiết kiệm"
        // vì một phép chia cho 0 ở đâu đó.
        for bogus in [0.0, -1.0, f64::NAN, f64::INFINITY] {
            let advice = recommend(Some(bogus));
            assert_eq!(advice.recommended.id, "auto", "giá trị {bogus} phải bị bỏ");
            assert_eq!(advice.measured_mbps, None);
        }
    }

    #[test]
    fn the_recommendation_only_moves_down_as_the_link_gets_worse() {
        // Đơn điệu: mạng tốt hơn không bao giờ được đề nghị preset thấp hơn.
        // Vi phạm điều này nghĩa là ngưỡng bị viết sai thứ tự, và người dùng sẽ
        // thấy "đo lại thì chất lượng đề nghị tụt" mà không hiểu vì sao.
        let rank = |id: &str| PRESETS.iter().position(|p| p.id == id).unwrap();
        let mut previous = 0;
        for mbps in [40.0, 25.0, 18.0, 12.0, 9.0, 6.0, 4.5, 3.0, 1.8, 0.5] {
            let current = rank(recommend(Some(mbps)).recommended.id);
            assert!(
                current >= previous,
                "{mbps} Mbps đề nghị preset cao hơn mức trước đó — ngưỡng sai thứ tự"
            );
            previous = current;
        }
    }

    #[test]
    fn json_uses_null_not_zero_for_an_unknown_measurement() {
        let json = advice_json(&recommend(None));
        assert!(json.contains("\"measured_mbps\":null"), "{json}");
        assert!(json.contains("\"recommended_preset\":\"auto\""), "{json}");
        // Không được để `0` — UI sẽ hiện "0 Mbps" và người dùng tưởng mạng hỏng.
        assert!(!json.contains("\"measured_mbps\":0,"), "{json}");
    }

    #[test]
    fn json_carries_the_measurement_when_there_is_one() {
        let json = advice_json(&recommend(Some(7.34)));
        assert!(json.contains("\"measured_mbps\":7.3"), "{json}");
        assert!(json.contains("\"recommended_preset\":\"smooth\""), "7.34×0.75=5.5 ⇒ smooth: {json}");
    }

    #[test]
    fn the_before_start_estimate_matches_the_default_preset() {
        // §6.10.2 câu 2: hiện "~8 Mbps" trước khi bấm Start. Spec ghi 8, và
        // bảng §6.10.1 cũng ghi 8 cho "Cân bằng" — test khoá hai con số bằng nhau.
        let (mbps, label) = estimate_before_start();
        assert_eq!(mbps, 8.0);
        assert_eq!(label, "Cân bằng");
    }
}
