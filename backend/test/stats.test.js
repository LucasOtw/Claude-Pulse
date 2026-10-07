import { test } from 'node:test';
import assert from 'node:assert/strict';
import { priceFor, costOf, modelLabel } from '../lib/pricing.js';
import { buildStats } from '../lib/stats.js';

test('tarifs : le préfixe le plus précis gagne', () => {
  assert.equal(priceFor('claude-opus-5-5').input, 4);
  assert.equal(priceFor('claude-opus-5').input, 5);
  assert.equal(priceFor('claude-opus-4-1-20250805').input, 15);
  assert.equal(priceFor('claude-sonnet-4-5-20250929').output, 15);
  assert.equal(priceFor('claude-fable-5-1').cacheRead, 0.25);
  assert.equal(priceFor('claude-haiku-4-5-20251001').input, 1);
  assert.equal(priceFor('claude-opus-9-9').input, 5, 'famille inconnue : repli');
  assert.equal(priceFor('<synthetic>'), null);
});

test('coût : écritures de cache 1,25× et 2×, lectures au tarif du modèle', () => {
  // 1 M de chaque sur Sonnet 5.5 : 2 + 10 + 2,5 + 4 + 0,2
  assert.equal(costOf('claude-sonnet-5-5', [1e6, 1e6, 1e6, 1e6, 1e6]), 18.7);
});

test('libellés de modèles', () => {
  assert.equal(modelLabel('claude-opus-5-5'), 'Opus 5.5');
  assert.equal(modelLabel('claude-sonnet-4-5-20250929'), 'Sonnet 4.5');
  assert.equal(modelLabel('claude-opus-4-20250514'), 'Opus 4');
  assert.equal(modelLabel('claude-3-5-haiku-20241022'), 'Haiku 3.5');
  assert.equal(modelLabel('claude-fable-5-1'), 'Fable 5.1');
});

test('statistiques par période, jour et modèle', () => {
  const st = buildStats(
    {
      s1: { '2026-10-07': { 'claude-opus-5-5': [0, 1e6, 0, 0, 0] }, '2026-09-01': { 'claude-opus-5-5': [1e6, 0, 0, 0, 0] } },
      s2: { '2026-10-02': { 'claude-haiku-4-5': [1e6, 0, 0, 0, 0] } },
    },
    '2026-10-07',
  );
  assert.equal(st.since, '2026-09-01');
  assert.deepEqual(st.periods.today, { tokens: 1e6, costUsd: 20 });
  assert.deepEqual(st.periods.week, { tokens: 2e6, costUsd: 21 });
  assert.deepEqual(st.periods.month, { tokens: 2e6, costUsd: 21 }, 'le 1er septembre est hors des 30 jours');
  assert.equal(st.totals.costUsd, 25);
  assert.equal(st.totals.output, 1e6);
  assert.equal(st.days.at(-1).costUsd, 20);
  assert.deepEqual(st.models.map((m) => [m.model, m.costUsd]), [['Opus 5.5', 24], ['Haiku 4.5', 1]]);
});
