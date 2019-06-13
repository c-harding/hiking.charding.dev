document.body.addEventListener('click', e => {
  const permalink = e.target.closest('.permalink');
  if (permalink === null) return;
  e.preventDefault();
  permalink.classList.remove('copied');
  clearTimeout(permalink.dataset.timeout);

  const input = permalink.querySelector('input');
  const linkText = permalink.querySelector('.linkText').innerText;
  input.setAttribute('size', linkText.length);
  input.value = permalink.closest('a').href;
  permalink.classList.add('copying');
  
  const range = document.createRange();
  range.selectNodeContents(input);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
  input.setSelectionRange(0, 1e9);
  
  document.execCommand('copy');
  input.blur();
  permalink.classList.add('copied');
  permalink.classList.remove('copying');
  permalink.dataset.timeout = setTimeout(() => {
    permalink.classList.remove('copied');
  }, 1000);
  document.activeElement.blur();
});

function changeHash(newHash) {
  const match = location.hash.match(/^(.*?)#category-([-\w]+)(.*)$/);
  if (match && match[2] == newHash) location.hash = match[1] + match[3];
  else if (match) location.hash = `${match[1]}#category-${newHash}${match[3]}`;
  else location.hash = `#category-${newHash}`;
}

function onHashChange() {
  const match = location.hash.match(/#category-([-\w]+)/);
  const category = match && match[1];

  const sheet = document.getElementById('category-style-sheet');
  
  sheet.innerHTML = category ? `
    .card:not(.${category}) { display: none; }

    .category-selector .${category}:not(:hover),
    .no-hover .category-selector .${category} {
      background-color: #ccc;
    }
  ` : '';
}
window.addEventListener("hashchange", onHashChange);
onHashChange();

document.body.classList.add(
  matchMedia('(hover)').matches ? 'can-hover' : 'no-hover'
);

document.querySelector('.category-selector').addEventListener('click', e => {
  const link = e.target.closest('.category-selector > li > a');
  if (link === null) return;
  changeHash(link.dataset.category);
  e.preventDefault();
});