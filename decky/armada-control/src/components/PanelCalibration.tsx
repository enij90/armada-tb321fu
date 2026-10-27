import { toaster } from "@decky/api";
import { ConfirmModal, DialogButton, Focusable, showModal } from "@decky/ui";
import { useEffect, useRef, useState } from "react";
import { calibratePanel, getPanelCalibration, getPanelRate, savePanel, setPanel, stepPanel } from "../backend";
import { t } from "../i18n";
import type { PanelAttr, PanelCalibration as PanelState, PanelRate } from "../types";
import { ButtonRow } from "./widgets";

const formatHz = (hz: number) => `${hz.toFixed(2)} Hz`;

export function PanelCalibration() {
  const [supported, setSupported] = useState(false);

  useEffect(() => {
    let cancelled = false;
    getPanelCalibration()
      .then((next) => { if (!cancelled) setSupported(next.supported); })
      .catch(() => undefined);
    return () => { cancelled = true; };
  }, []);

  if (!supported) return null;

  return (
    <ButtonRow layout="below" label={t("display.label")} onClick={() => showModal(<PanelCalibrationModal />)}>
      {t("calibration.launch")}
    </ButtonRow>
  );
}

function PanelCalibrationModal({ closeModal }: { closeModal?: () => void }) {
  const [state, setState] = useState<PanelState | null>(null);
  const [rate, setRate] = useState<PanelRate | null | undefined>(undefined);
  const [busy, setBusy] = useState<"measuring" | "calibrating" | "saving" | null>(null);
  const [rangeEnd, setRangeEnd] = useState<"faster" | "slower" | null>(null);
  const busyRef = useRef(false);
  const closing = useRef(false);
  const pending = useRef<Promise<void>>(Promise.resolve());
  const openedWith = useRef<PanelState["live"]>(undefined);

  const refresh = async () => {
    const [next, nextRate] = await Promise.all([getPanelCalibration(), getPanelRate()]);
    setState(next);
    setRate(nextRate);
    return next;
  };

  const setLive = (attr: PanelAttr, value: number) =>
    setState((current) => current && { ...current, live: { ...current.live!, [attr]: value } });

  const run = (kind: "measuring" | "calibrating" | "saving", action: () => Promise<void>) => {
    if (busyRef.current || closing.current) return;
    busyRef.current = true;
    setBusy(kind);
    pending.current = action()
      .catch((error) => {
        if (!closing.current) toaster.toast({ title: t("display.calibrateFailed"), body: String(error) });
      })
      .finally(() => {
        busyRef.current = false;
        setBusy(null);
      });
  };

  useEffect(() => {
    run("measuring", async () => {
      openedWith.current = (await refresh().catch(() => { setRate(null); return null; }))?.live;
    });
  }, []);

  const attr = rate?.attr ?? null;
  const live = attr ? state?.live?.[attr] ?? null : null;
  const fallback = attr ? state?.defaults?.[attr] ?? null : null;

  const auto = () =>
    run("calibrating", async () => {
      setRangeEnd(null);
      try {
        await calibratePanel();
      } catch {
        if (!closing.current) toaster.toast({ title: t("display.calibrateFailed"), body: t("display.errorCalibrate") });
      }
      await refresh();
    });

  const step = (direction: "faster" | "slower") =>
    run("measuring", async () => {
      if (!attr || live == null) return;
      setLive(attr, direction === "faster" ? live - 1 : live + 1);
      try {
        const result = await stepPanel(attr, direction);
        setRangeEnd(result.limit === "range" ? direction : null);
        setLive(attr, result.value);
        setRate((current) => current && { ...current, hz: result.hz });
      } catch (error) {
        setLive(attr, live);
        throw error;
      }
    });

  // Save on the panel default clears the setting.
  const reset = () =>
    run("measuring", async () => {
      if (!attr || fallback == null) return;
      await setPanel(attr, fallback);
      setRangeEnd(null);
      setLive(attr, fallback);
      await refresh();
    });

  const save = () =>
    run("saving", async () => {
      if (!attr) return;
      // A Cancel after this point must not undo what is being saved.
      closing.current = true;
      try {
        await savePanel(attr);
      } catch (error) {
        closing.current = false;
        throw error;
      }
      closeModal?.();
    });

  const cancel = async () => {
    if (closing.current) return;
    closing.current = true;
    await pending.current;
    const current = (await getPanelCalibration().catch(() => null))?.live;
    let restored = true;
    for (const [name, value] of Object.entries(openedWith.current ?? {}) as [PanelAttr, number | null][]) {
      if (value != null && current?.[name] !== value) {
        restored = (await setPanel(name, value).then(() => true, () => false)) && restored;
      }
    }
    if (!restored) toaster.toast({ title: t("display.calibrateFailed"), body: t("display.errorRestore") });
    closeModal?.();
  };

  // Positive is faster: a lower frame length is a faster refresh.
  const offset = live != null && fallback != null ? fallback - live : null;
  const headline = offset == null ? "-" : offset < 0 ? `−${-offset}` : `+${offset}`;
  const measured = rate === undefined || busy === "measuring" || busy === "calibrating"
    ? t("display.measuring")
    : rate?.hz != null
      ? formatHz(rate.hz)
      : t("display.unavailable");

  const controlsDisabled = busy != null || !attr;
  const columnWidth = "192px";
  const stepButton = { width: "2em", minWidth: "2em", height: "2em", flex: "none", fontSize: "20px", padding: 0, display: "flex", alignItems: "center", justifyContent: "center" };

  return (
    <ConfirmModal
      strOKButtonText={t("common.save")}
      strMiddleButtonText={t("display.reset")}
      strCancelButtonText={t("common.cancel")}
      bOKDisabled={controlsDisabled || live == null}
      bMiddleDisabled={controlsDisabled || fallback == null || live === fallback}
      onOK={save}
      onMiddleButton={reset}
      onCancel={cancel}
    >
      <div style={{ textAlign: "center", fontSize: "40px", fontWeight: 600, fontVariantNumeric: "tabular-nums" }}>
        {measured}
      </div>
      <div style={{ display: "flex", justifyContent: "center", margin: "36px 0 0" }}>
        <DialogButton style={{ width: columnWidth }} onClick={auto} disabled={controlsDisabled}>
          {t(busy === "calibrating" ? "display.calibrating" : "display.autoCalibrate")}
        </DialogButton>
      </div>
      <Focusable flow-children="row" style={{ display: "flex", alignItems: "center", justifyContent: "space-between", width: columnWidth, margin: "16px auto 10px" }}>
        <DialogButton style={stepButton} onClick={() => step("slower")} disabled={controlsDisabled || rangeEnd === "slower"}>−</DialogButton>
        <div style={{ width: "3em", textAlign: "center", fontSize: "20px", fontVariantNumeric: "tabular-nums" }}>{headline}</div>
        <DialogButton style={stepButton} onClick={() => step("faster")} disabled={controlsDisabled || rangeEnd === "faster"}>+</DialogButton>
      </Focusable>
    </ConfirmModal>
  );
}
