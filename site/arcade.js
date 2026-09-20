(function () {
  const cards = Array.from(document.querySelectorAll(".game"));
  if (!cards.length) return;

  let index = Math.max(0, cards.findIndex((el) => el.classList.contains("is-selected")));

  function select(next) {
    index = (next + cards.length) % cards.length;
    cards.forEach((el, i) => el.classList.toggle("is-selected", i === index));
    cards[index].focus({ preventScroll: true });
  }

  document.addEventListener("keydown", (event) => {
    if (event.key === "ArrowRight" || event.key === "ArrowDown") {
      event.preventDefault();
      select(index + 1);
    } else if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
      event.preventDefault();
      select(index - 1);
    } else if (event.key === "Enter") {
      event.preventDefault();
      window.location.href = cards[index].getAttribute("href");
    } else if (/^[1-9]$/.test(event.key)) {
      const jump = Number(event.key) - 1;
      if (cards[jump]) {
        event.preventDefault();
        select(jump);
        window.location.href = cards[jump].getAttribute("href");
      }
    }
  });

  cards.forEach((el, i) => {
    el.addEventListener("mouseenter", () => select(i));
    el.addEventListener("focus", () => select(i));
  });
})();
