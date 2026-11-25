"use strict";
// Each call uses the current frame only. Never combine different offers.
function parseOffer(text) {
    const clean = text.normalize("NFKC").toLowerCase();
    if (!/\b(accepter|livraison|livrer|accept|delivery|aceitar|entrega|exclusif|exclusive|correspondre)\b/.test(clean)) return null;
    const nums = token => Number(token.replace(",", "."));
    const prices = [...clean.matchAll(/(?:€\s*(\d+(?:[,.]\d{1,2})?)|(\d+(?:[,.]\d{1,2})?)\s*(?:€|eur\b))(?!\s*\/)/g)]
        .map(match => nums(match[1] || match[2]));
    const amounts = [...new Set(prices)];
    if (amounts.length !== 1 || amounts[0] <= 0) return null;
    function values(pattern) {
        return [...clean.matchAll(pattern)].map(m => nums(m[1]));
    }
    const ds = values(/(\d+(?:[,.]\d+)?)\s*km\b/g);
    const ts = values(/(\d+(?:[,.]\d+)?)\s*min(?:utes?)?\b/g);
    const hasHours = /\d\s*(?:h(?:eures?)?|hr)\b|\d\s*h\s*\d/.test(clean);
    // Several distances or durations may describe individual legs. Do not guess the total.
    const km = ds.length === 1 && ds[0] > 0 ? ds[0] : null;
    const minutes = ts.length === 1 && ts[0] > 0 && !hasHours ? ts[0] : null;
    if (!km && !minutes) return null;
    return {fare: amounts[0], km, minutes};
}
function analyse(text, reserve, perKm, goal) {
    const o = parseOffer(text);
    if (!o) return null;
    const eur = n => n.toFixed(2).replace(".", ",") + " €";
    const gross = o.minutes ? o.fare * 60 / o.minutes : null;
    const fuelKnown = Number.isFinite(perKm) && perKm >= 0 && o.km !== null;
    const left = fuelKnown ? o.fare * (1 - reserve / 100) - o.km * perKm : null;
    const rate = left !== null && o.minutes ? left * 60 / o.minutes : null;
    let title = eur(o.fare) + " · oferta";
    let detail = [];
    if (rate !== null) {
        title = (rate >= goal ? "Acima ou na meta" : "Abaixo da meta") + " · " + eur(rate) + "/h";
        detail.push(eur(left) + " após reserva e gasóleo estimados");
    } else {
        if (gross !== null) detail.push(eur(gross) + "/h brutos");
        if (left !== null) detail.push(eur(left) + " após custos estimados");
        if (!fuelKnown) detail.push("gasóleo por estimar");
        if (o.minutes === null) detail.push("duração por confirmar");
    }
    if (o.km !== null) detail.push(eur(o.fare / o.km) + "/km brutos");
    else detail.push("distância por confirmar");
    return {...o, gross, left, rate, title, body: detail.join(" · ")};
}
if (typeof module !== "undefined") module.exports = {parseOffer, analyse};
