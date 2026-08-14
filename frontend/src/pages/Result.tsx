import { useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { upgradeCpuGpu, upgradeRam, type BuildResponse, type Part } from "../api";
import LoadingBar from "../components/LoadingBar";

const CATEGORY_LABELS: Record<string, string> = {
  cpu: "CPU", gpu: "GPU", mboard: "메인보드", ram: "RAM",
  cooler: "쿨러", psu: "PSU", case: "케이스", ssd: "저장장치(SSD)", hdd: "보조 저장장치(HDD)",
};
const CATEGORY_ORDER = ["cpu", "mboard", "gpu", "ram", "ssd", "hdd", "psu", "cooler", "case"];

// 오늘 DB에 새로 추가한 확장 스펙 컬럼(카테고리별)을 부품 카드에 보조 텍스트로 노출한다.
// 값이 없는 카테고리(아직 스크래핑 안 된 상품 등)는 조용히 생략된다.
function extraSpecLine(category: string, part: Part): string | null {
  const items: string[] = [];
  const num = (v: unknown) => typeof v === "number";

  switch (category) {
    case "cpu":
      // socket도 add_compat_columns.sql 때부터 있던 기존 컬럼인데 표시 목록에서 빠져 있었다.
      if (part.socket) items.push(`소켓 ${part.socket}`);
      if (num(part.cinebench_single) && num(part.cinebench_multi)) {
        items.push(`시네벤치 싱글 ${part.cinebench_single} · 멀티 ${part.cinebench_multi}`);
      }
      if (part.memory_support) items.push(`메모리 ${part.memory_support}`);
      break;
    case "gpu":
      // length_mm/recommended_psu_w/power_connector도 add_compat_columns.sql 때부터
      // 있던 기존 컬럼인데 표시 목록에서 빠져 있었다.
      if (num(part.length_mm)) items.push(`길이 ${part.length_mm}mm`);
      if (part.power_connector) items.push(`전원 커넥터 ${part.power_connector}`);
      if (num(part.recommended_psu_w)) items.push(`권장 파워 ${part.recommended_psu_w}W`);
      if (part.output_ports) items.push(`출력단자 ${part.output_ports}`);
      if (num(part.power_draw_w)) items.push(`사용전력 ${part.power_draw_w}W`);
      break;
    case "mboard": {
      // socket/ram_type은 add_compat_columns.sql 때부터 있던 기존 컬럼인데 표시
      // 목록에서 빠져 있었다(실사용자 발견: "메인보드에 DDR4/DDR5 여부가 안 보인다").
      if (part.socket) items.push(`소켓 ${part.socket}`);
      if (part.ram_type) items.push(String(part.ram_type));
      const slots: string[] = [];
      if (num(part.pcie_x16_count)) slots.push(`PCIe x16 ${part.pcie_x16_count}개`);
      if (num(part.m2_slot_count)) slots.push(`M.2 ${part.m2_slot_count}개`);
      if (num(part.sata3_count)) slots.push(`SATA3 ${part.sata3_count}개`);
      if (slots.length) items.push(slots.join(" · "));
      if (part.pcie_version) items.push(String(part.pcie_version));
      break;
    }
    case "ram":
      // ram_type도 add_compat_columns.sql 때부터 있던 기존 컬럼인데 표시 목록에서 빠져 있었다.
      if (part.ram_type) items.push(String(part.ram_type));
      if (num(part.heatsink_height_mm)) items.push(`방열판 높이 ${part.heatsink_height_mm}mm`);
      break;
    case "psu": {
      // rated_w/form_factor는 add_compat_columns.sql 때부터 있던 기존 컬럼인데
      // 표시 목록에서 빠져 있었다.
      if (num(part.rated_w)) items.push(`정격출력 ${part.rated_w}W`);
      if (part.form_factor) items.push(`폼팩터 ${part.form_factor}`);
      if (num(part.depth_mm)) items.push(`깊이 ${part.depth_mm}mm`);
      const certs: string[] = [];
      if (part.eta_certification) certs.push(`ETA ${part.eta_certification}`);
      if (part.lambda_certification) certs.push(`LAMBDA ${part.lambda_certification}`);
      if (certs.length) items.push(certs.join(" · "));
      if (part.pcie_16pin_connector) items.push(`${part.pcie_16pin_connector} 네이티브 지원`);
      break;
    }
    case "cooler":
      // support_sockets/tdp_rating_w는 add_compat_columns.sql·add_cooler_tdp_column.sql
      // 때부터 있던 기존 컬럼(오늘 신설한 확장 컬럼이 아님) — 표시 목록에서 빠져 있었다
      // (실사용자 발견: "쿨러 카드에 소켓/TDP가 안 보인다").
      if (part.support_sockets) items.push(`지원 소켓 ${part.support_sockets}`);
      if (num(part.tdp_rating_w)) items.push(`TDP ${part.tdp_rating_w}W`);
      break;
    case "case": {
      // support_form_factors/max_vga_length_mm/max_cooler_height_mm/
      // support_psu_form_factors는 add_compat_columns.sql 때부터 있던 기존
      // 호환성 컬럼(오늘 신설한 확장 컬럼이 아님) — 표시 목록에서 빠져 있었다.
      if (part.support_form_factors) items.push(`지원보드 ${part.support_form_factors}`);
      const clearance: string[] = [];
      if (num(part.max_vga_length_mm)) clearance.push(`VGA ${part.max_vga_length_mm}mm`);
      if (num(part.max_cooler_height_mm)) clearance.push(`쿨러높이 ${part.max_cooler_height_mm}mm`);
      if (clearance.length) items.push(clearance.join(" · "));
      if (part.support_psu_form_factors) items.push(`지원파워 ${part.support_psu_form_factors}`);
      const psu: string[] = [];
      if (part.psu_position) psu.push(`파워위치 ${part.psu_position}`);
      if (num(part.psu_max_length_mm)) psu.push(`파워장착길이 ${part.psu_max_length_mm}mm`);
      if (psu.length) items.push(psu.join(" · "));
      if (num(part.ext_width_mm) && num(part.ext_depth_mm) && num(part.ext_height_mm)) {
        items.push(`외형 ${part.ext_width_mm}×${part.ext_depth_mm}×${part.ext_height_mm}mm`);
      }
      if (part.panel_type) items.push(String(part.panel_type));
      if (num(part.fan_count)) items.push(`쿨링팬 ${part.fan_count}개`);
      break;
    }
  }
  return items.length ? items.join(" · ") : null;
}

export interface Selection {
  budgetKrw: number;
  gameTitles: string[];
  usageNames: string[];
  placement: string;
  rgb: string;
  mode: "cost" | "perf";
}

function PartThumbnail({ part, onEnlarge }: { part: Part; onEnlarge: (url: string, name: string) => void }) {
  if (!part.image_url) {
    return <div className="part-thumb part-thumb-empty">?</div>;
  }
  return (
    <img
      src={part.image_url}
      alt={part.name}
      className="part-thumb"
      onClick={() => onEnlarge(part.image_url!, part.name)}
    />
  );
}

function ImageLightbox({ url, name, onClose }: { url: string; name: string; onClose: () => void }) {
  return (
    <div className="lightbox-backdrop" onClick={onClose}>
      <div className="lightbox-content" onClick={(e) => e.stopPropagation()}>
        <img src={url} alt={name} />
        <p className="lightbox-caption">{name}</p>
        <button type="button" className="lightbox-close" onClick={onClose}>닫기 ✕</button>
      </div>
    </div>
  );
}

export default function Result() {
  const location = useLocation();
  const navigate = useNavigate();
  const state = location.state as { result?: BuildResponse; selection?: Selection } | null;
  const initial = state?.result;
  const selection = state?.selection;

  const [result, setResult] = useState<BuildResponse | undefined>(initial);
  const [history, setHistory] = useState<BuildResponse[]>([]);
  const [actionLoading, setActionLoading] = useState(false);
  const [actionError, setActionError] = useState("");
  const [lightbox, setLightbox] = useState<{ url: string; name: string } | null>(null);

  if (!result) {
    return (
      <div className="app-shell">
        <div className="error-banner">불러올 견적 정보가 없습니다.</div>
        <Link to="/">← 새 견적 만들기</Link>
      </div>
    );
  }

  const runAction = async (fn: () => Promise<BuildResponse>, failMessage: string) => {
    setActionLoading(true);
    setActionError("");
    try {
      const next = await fn();
      if (next.status !== "ok") {
        setActionError(next.message || failMessage);
        return;
      }
      setHistory((h) => [...h, result]);
      setResult(next);
    } catch {
      setActionError(failMessage);
    } finally {
      setActionLoading(false);
    }
  };

  const handleRevert = () => {
    if (history.length === 0) return;
    setResult(history[history.length - 1]);
    setHistory((h) => h.slice(0, -1));
    setActionError("");
  };

  const handleConfirm = () => {
    navigate("/confirm", { state: { result, selection } });
  };

  if (result.status !== "ok") {
    return (
      <div className="app-shell">
        <h1>견적 결과</h1>
        <div className="error-banner">{result.message || "해당하는 상품을 찾을 수 없습니다."}</div>
        <Link to="/">← 새 견적 만들기</Link>
      </div>
    );
  }

  const parts = result.parts!;

  return (
    <div className="app-shell">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1rem" }}>
        <h1>견적 결과</h1>
        <Link to="/">← 새 견적 만들기</Link>
      </div>

      {actionError && <div className="error-banner">{actionError}</div>}

      {selection && (
        <div className="result-section">
          <h3>📋 선택하신 옵션</h3>
          <ul className="parts-list">
            <li className="part-item">
              <span><strong>예산:</strong> {selection.budgetKrw.toLocaleString()}원</span>
            </li>
            <li className="part-item">
              <span><strong>견적 유형:</strong> {selection.mode === "cost" ? "가성비" : "성능"}</span>
            </li>
            {selection.gameTitles.length > 0 && (
              <li className="part-item">
                <span><strong>게임:</strong> {selection.gameTitles.join(", ")}</span>
              </li>
            )}
            {selection.usageNames.length > 0 && (
              <li className="part-item">
                <span><strong>PC 용도:</strong> {selection.usageNames.join(", ")}</span>
              </li>
            )}
            <li className="part-item">
              <span><strong>배치할 위치:</strong> {selection.placement}</span>
            </li>
            <li className="part-item">
              <span><strong>RGB 선호도:</strong> {selection.rgb}</span>
            </li>
          </ul>
        </div>
      )}

      {result.review_notes && result.review_notes.length > 0 && (
        <div className="result-section review-notes-section">
          <h3>🤖 AI 검수 결과</h3>
          <ul className="parts-list">
            {result.review_notes.map((note, i) => (
              <li key={i} className="part-item">
                <span>{note}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="result-section">
        <h3>부품 목록</h3>
        <ul className="parts-list">
          {CATEGORY_ORDER.filter((k) => parts[k]).map((key) => {
            const part = parts[key];
            const qty = part.quantity ?? 1;
            const extra = extraSpecLine(key, part);
            return (
              <li key={key} className="part-item part-item-with-thumb">
                <PartThumbnail part={part} onEnlarge={(url, name) => setLightbox({ url, name })} />
                <span className="part-name-block">
                  <strong>{CATEGORY_LABELS[key] ?? key}:</strong> {part.name}
                  {qty > 1 && part.unit_price_krw != null && (
                    <span className="part-unit-price"> (개당 {part.unit_price_krw.toLocaleString()}원 × {qty}개)</span>
                  )}
                  {extra && <span className="part-extra-specs">{extra}</span>}
                </span>
                <span className="part-price">{part.price_krw.toLocaleString()}원</span>
              </li>
            );
          })}
        </ul>
      </div>

      <div className="result-section">
        <h3>총 견적 금액</h3>
        <div className="total-price">{result.total_price_krw!.toLocaleString()}원</div>
      </div>

      <div className="result-section">
        <h3>⬆️ 업그레이드</h3>
        {actionLoading && <LoadingBar text="새 조합을 찾는 중입니다..." />}
        <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
          <button
            type="button"
            className="submit-button"
            style={{ width: "auto" }}
            disabled={actionLoading}
            onClick={() =>
              runAction(() => upgradeCpuGpu(result), "CPU/GPU를 한 단계 위로 올릴 수 없습니다(다른 부품 다운그레이드 발생 또는 최고 등급).")
            }
          >
            CPU/GPU 성능 개선
          </button>
          <button
            type="button"
            className="submit-button secondary"
            style={{ width: "auto" }}
            disabled={actionLoading}
            onClick={() => runAction(() => upgradeRam(result), "RAM 용량 개선은 현재 지원되지 않습니다(실제 데이터에 RAM 용량 정보가 아직 없습니다).")}
            title="실제 데이터에 RAM 용량 정보가 채워지면 지원될 예정입니다"
          >
            RAM 용량 개선 (준비중)
          </button>
        </div>
      </div>

      <div className="result-section" style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
        <button
          type="button"
          className="submit-button secondary"
          style={{ width: "auto" }}
          disabled={actionLoading || history.length === 0}
          onClick={handleRevert}
        >
          이전 단계로 되돌리기
        </button>
        <button
          type="button"
          className="submit-button"
          style={{ width: "auto" }}
          disabled={actionLoading}
          onClick={handleConfirm}
        >
          이 견적으로 확정
        </button>
      </div>

      {lightbox && (
        <ImageLightbox url={lightbox.url} name={lightbox.name} onClose={() => setLightbox(null)} />
      )}
    </div>
  );
}
