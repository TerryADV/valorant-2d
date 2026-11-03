const menuButton = document.querySelector('.menu-toggle');
const navigation = document.querySelector('.nav-links');

if (menuButton && navigation) {
  menuButton.addEventListener('click', () => {
    const isOpen = navigation.classList.toggle('is-open');
    menuButton.setAttribute('aria-expanded', String(isOpen));
    menuButton.setAttribute('aria-label', isOpen ? 'Close menu' : 'Open menu');
  });

  navigation.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', () => {
      navigation.classList.remove('is-open');
      menuButton.setAttribute('aria-expanded', 'false');
      menuButton.setAttribute('aria-label', 'Open menu');
    });
  });
}

const agentAbilities = {
  jett: {
    name: 'JETT',
    abilities: [
      ['C', 'Cloudburst', 'Throw a smoke cloud that briefly blocks vision.', 'jett/cloud_burst.png'],
      ['Q', 'Updraft', 'Launch yourself upward to reach elevated positions.', 'jett/updraft.png'],
      ['E', 'Tailwind', 'Activate a gust that lets Jett dash quickly.', 'jett/tailwind.png'],
      ['X', 'Blade Storm', 'Equip highly accurate throwing knives.', 'jett/blade_storm.png'],
    ],
  },
  phoenix: {
    name: 'PHOENIX',
    abilities: [
      ['C', 'Blaze', 'Raise a wall of fire that blocks vision and can heal Phoenix.', 'phoenix/blaze.png'],
      ['Q', 'Hot Hands', 'Throw fire onto the ground to damage enemies and heal Phoenix.', 'phoenix/hot_hands.png'],
      ['E', 'Curveball', 'Throw a flash that blinds anyone looking at it.', 'phoenix/curve_ball.png'],
      ['X', 'Run It Back', 'Mark your location and return to it if you take fatal damage during the ability.', 'phoenix/run_it_back.png'],
    ],
  },
  sage: {
    name: 'SAGE',
    abilities: [
      ['C', 'Barrier Orb', 'Create a solid wall that blocks movement and lines of sight.', 'sage/barrier_orb.png'],
      ['Q', 'Slow Orb', 'Cover an area with a field that slows anyone who crosses it.', 'sage/slow_orb.png'],
      ['E', 'Healing Orb', 'Restore health to Sage or an ally.', 'sage/healing_orb.png'],
      ['X', 'Resurrection', 'Bring a fallen ally back to life.', 'sage/resurrection.png'],
    ],
  },
};

const abilityPanel = document.querySelector('#agent-abilities');
const abilityAgentName = document.querySelector('#ability-agent-name');
const abilityList = document.querySelector('#ability-list');
const abilityClose = document.querySelector('.ability-close');
const agentButtons = [...document.querySelectorAll('.agent-select')];

function closeAbilities() {
  if (!abilityPanel) return;
  abilityPanel.hidden = true;
  agentButtons.forEach((button) => button.setAttribute('aria-expanded', 'false'));
}

agentButtons.forEach((button) => {
  button.addEventListener('click', () => {
    const selectedAgent = agentAbilities[button.dataset.agent];
    if (!selectedAgent) return;

    const alreadyOpen = button.getAttribute('aria-expanded') === 'true';
    agentButtons.forEach((agentButton) => agentButton.setAttribute('aria-expanded', 'false'));
    if (alreadyOpen) {
      closeAbilities();
      return;
    }

    button.setAttribute('aria-expanded', 'true');
    abilityAgentName.textContent = selectedAgent.name;
    abilityList.replaceChildren(...selectedAgent.abilities.map(([key, name, description, icon]) => {
      const item = document.createElement('article');
      item.className = 'ability-item';
      const top = document.createElement('div');
      top.className = 'ability-item-top';
      const image = document.createElement('img');
      image.src = `imagenes/abilities/${icon}`;
      image.alt = '';
      const keyLabel = document.createElement('span');
      keyLabel.className = 'ability-key';
      keyLabel.textContent = key;
      top.append(image, keyLabel);
      const title = document.createElement('h4');
      title.textContent = name;
      const copy = document.createElement('p');
      copy.textContent = description;
      item.append(top, title, copy);
      return item;
    }));
    abilityPanel.hidden = false;
    abilityPanel.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  });
});

abilityClose?.addEventListener('click', closeAbilities);
