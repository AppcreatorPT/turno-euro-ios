const assert = require('node:assert/strict');
const {analyse, parseOffer} = require('../App/offer.js');
const text = "Livraison\n6,40 €\n20 min (4 km)\nAccepter";
const r = analyse(text, 21.3, 0.14, 15);
assert.equal(r.gross, 19.2);
assert.ok(Math.abs(r.left - 4.4768) < 0.00001);
assert.ok(Math.abs(r.rate - 13.4304) < 0.00001);
assert.match(r.title, /Abaixo da meta/);
assert.match(analyse(text, 21.3, 0.14, 12).title, /Acima ou na meta/);
for (const variant of ['€6.40', '6,40 EUR', '6,40\u202f€']) {
    assert.deepEqual(parseOffer(text.replace('6,40 €', variant)), parseOffer(text));
}
assert.equal(analyse(text, 21.3, null, 15).rate, null);
assert.equal(analyse(text.replace('4 km',''),21.3,0.14,15).left, null);
assert.equal(analyse(text.replace('20 min',''),21.3,0.14,15).gross, null);
assert.equal(parseOffer(text + '\n+2 €'), null);
assert.equal(parseOffer('Solde 6,40 €\n20 min (4 km)'), null);
assert.equal(parseOffer(text.replace('20 min','1 h 20 min')).minutes, null);
assert.equal(parseOffer(text.replace('4 km','2 km puis 4 km')).km, null);
assert.equal(parseOffer(text.replace('€','$')), null);
assert.equal(parseOffer('Livraison 10 €/h 10 min 2 km'), null);
console.log('OK — leitura de ofertas, valores em euros, custos, metas e dados ambíguos.');
