// Service area for now: Marsella 1 (Q1–Q7) and Marsella 2 (Q8–Q14).
export const ZONAS = {
  'Marsella 1': ['Q1', 'Q2', 'Q3', 'Q4', 'Q5', 'Q6', 'Q7'],
  'Marsella 2': ['Q8', 'Q9', 'Q10', 'Q11', 'Q12', 'Q13', 'Q14'],
};

// Fills a Zona <select> and a dependent Quartier <select>. onChange(zona, quartier) fires on every change.
export function bindZonaPicker(zonaEl, quartierEl, { zona = '', quartier = '', onChange } = {}) {
  zonaEl.innerHTML = '<option value="">Selecciona zona</option>' + Object.keys(ZONAS).map(z => `<option value="${z}">${z}</option>`).join('');
  const fillQ = (z, keep = '') => {
    quartierEl.innerHTML = z
      ? '<option value="">Selecciona quartier</option>' + ZONAS[z].map(q => `<option value="${q}">${q}</option>`).join('')
      : '<option value="">Primero elige la zona</option>';
    quartierEl.disabled = !z;
    quartierEl.value = keep && z && ZONAS[z].includes(keep) ? keep : '';
  };
  zonaEl.onchange = () => { fillQ(zonaEl.value); onChange && onChange(zonaEl.value, quartierEl.value); };
  quartierEl.onchange = () => onChange && onChange(zonaEl.value, quartierEl.value);
  zonaEl.value = ZONAS[zona] ? zona : '';
  fillQ(zonaEl.value, quartier);
  onChange && onChange(zonaEl.value, quartierEl.value);
}

// "Marsella 1 · Q3" -> { zona, quartier }
export function parseZonaLabel(label) {
  const m = String(label || '').match(/^(Marsella [12])\s*·\s*(Q\d+)$/);
  return m ? { zona: m[1], quartier: m[2] } : { zona: '', quartier: '' };
}
export const zonaLabel = (zona, quartier) => [zona, quartier].filter(Boolean).join(' · ');
