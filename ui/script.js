const phoneContainer = document.getElementById('phone-container');
const contactsView = document.getElementById('contacts-view');
const messagesView = document.getElementById('messages-view');
const screenTitle = document.getElementById('screen-title');
const contactList = document.getElementById('contact-list');
const noContacts = document.getElementById('no-contacts');
const messageHistory = document.getElementById('message-history');
const messageInput = document.getElementById('message-input');

const softLeftBtn = document.getElementById('soft-left');
const softRightBtn = document.getElementById('soft-right');
const callLeftBtn = document.getElementById('call-left');
const callRightBtn = document.getElementById('call-right');
const navUpBtn = document.getElementById('nav-up');
const navDownBtn = document.getElementById('nav-down');

const footerLeft = document.getElementById('footer-left');
const footerRight = document.getElementById('footer-right');

const popup = document.getElementById('message-popup');
const popupContact = document.getElementById('popup-contact');
const popupText = document.getElementById('popup-text');

let currentView = 'contacts';
let currentContact = null;
let contactsData = {};
let selectedContactIndex = 0;
let locales = {};
let phoneOpen = false;
let popupTimer = null;
let audioContext = null;

const getAudioContext = () => {
    if (!audioContext) {
        const AudioCtx = window.AudioContext || window.webkitAudioContext;
        if (!AudioCtx) return null;
        audioContext = new AudioCtx();
    }

    if (audioContext.state === 'suspended') {
        audioContext.resume().catch(() => {});
    }

    return audioContext;
};

/** Plays a short non-copyrighted retro keypad tone using two standard telephone frequencies. */
const playButtonSound = (type = 'key', key = '') => {
    const ctx = getAudioContext();
    if (!ctx) return;

    const dtmf = {
        '1': [697, 1209], '2': [697, 1336], '3': [697, 1477],
        '4': [770, 1209], '5': [770, 1336], '6': [770, 1477],
        '7': [852, 1209], '8': [852, 1336], '9': [852, 1477],
        '*': [941, 1209], '0': [941, 1336], '#': [941, 1477]
    };

    const pairs = dtmf[key] || (type === 'navigate' ? [440, 660] : type === 'send' ? [659, 988] : [520, 780]);
    const now = ctx.currentTime;
    const duration = type === 'send' ? 0.105 : 0.055;

    pairs.forEach((frequency, index) => {
        const oscillator = ctx.createOscillator();
        const gain = ctx.createGain();

        oscillator.type = 'sine';
        oscillator.frequency.setValueAtTime(frequency, now);
        gain.gain.setValueAtTime(0.0001, now);
        gain.gain.exponentialRampToValueAtTime(index === 0 ? 0.028 : 0.022, now + 0.004);
        gain.gain.exponentialRampToValueAtTime(0.0001, now + duration);

        oscillator.connect(gain);
        gain.connect(ctx.destination);
        oscillator.start(now);
        oscillator.stop(now + duration + 0.005);
    });
};

/** Plays a short incoming-message chime distinct from the keypad sounds. */
const playMessageSound = () => {
    const ctx = getAudioContext();
    if (!ctx) return;

    [784, 988].forEach((frequency, index) => {
        const oscillator = ctx.createOscillator();
        const gain = ctx.createGain();
        const start = ctx.currentTime + index * 0.085;

        oscillator.type = 'triangle';
        oscillator.frequency.setValueAtTime(frequency, start);
        gain.gain.setValueAtTime(0.0001, start);
        gain.gain.exponentialRampToValueAtTime(0.035, start + 0.006);
        gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.07);

        oscillator.connect(gain);
        gain.connect(ctx.destination);
        oscillator.start(start);
        oscillator.stop(start + 0.075);
    });
};

/** Shows a small SMS popup only while the phone itself is closed. */
const showIncomingPopup = (contactId, text) => {
    if (phoneOpen) return;

    const contact = contactsData[contactId];
    popupContact.textContent = contact?.name || contactId || 'Message';

    const plainText = normalizeMessageText(text)
        .replace(/```[\s\S]*?```/g, '[code]')
        .replace(/[*_`#>-]/g, '')
        .replace(/\s+/g, ' ')
        .trim();

    popupText.textContent = plainText || 'New message';

    popup.classList.remove('show');
    void popup.offsetWidth;
    popup.classList.add('show');

    clearTimeout(popupTimer);
    popupTimer = setTimeout(() => {
        popup.classList.remove('show');
    }, 4650);

    playMessageSound();
};

/** Adds button sounds to the physical phone controls without polling the UI. */
const bindButtonSounds = () => {
    document.querySelectorAll('.phone-button, .nav-button').forEach((button) => {
        button.addEventListener('click', () => {
            const key = button.dataset.key || '';
            if (key) {
                playButtonSound('key', key);
            } else if (button.classList.contains('nav-button')) {
                playButtonSound('navigate');
            } else if (button.id === 'soft-left' || button.id === 'soft-right') {
                playButtonSound(currentView === 'messages' && button.id === 'soft-left' ? 'send' : 'soft');
            } else {
                playButtonSound('soft');
            }
        });
    });
};

/** Sends a NUI request to the Lua client callback. */
const post = (event, data = {}) => {
    fetch(`https://${GetParentResourceName()}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).catch((error) => {
        console.error(`[flex_brickphone] NUI request failed: ${event}`, error);
    });
};

/** Applies localized strings to text and placeholder elements. */
const applyLocales = () => {
    document.querySelectorAll('[data-locale], [data-locale-placeholder]').forEach((el) => {
        const isPlaceholder = el.hasAttribute('data-locale-placeholder');
        const key = isPlaceholder
            ? el.getAttribute('data-locale-placeholder')
            : el.getAttribute('data-locale');
        const prop = isPlaceholder ? 'placeholder' : 'textContent';

        if (locales[key]) el[prop] = locales[key];
    });
};

/** Displays the contact list view and clears the current conversation. */
const showContactsView = () => {
    currentContact = null;
    messagesView.classList.add('hidden');
    contactsView.classList.remove('hidden');
    messageInput.value = '';
    messageHistory.innerHTML = '';
    currentView = 'contacts';
    updateFooter();
    updateScreenTitle(locales['ui.contacts'] || 'Contacts');
    renderContacts(contactsData);
};

/** Displays a contact conversation and focuses its message input. */
const showMessagesView = (contact) => {
    currentContact = contact;
    contactsView.classList.add('hidden');
    messagesView.classList.remove('hidden');
    currentView = 'messages';
    updateFooter();
    updateScreenTitle(contact.name);
    messageInput.focus();
};

/** Updates the two phone soft-key labels for the current view. */
const updateFooter = () => {
    if (currentView === 'contacts') {
        footerLeft.textContent = locales['ui.select'] || 'Select';
        footerRight.textContent = locales['ui.close'] || 'Close';
    } else {
        footerLeft.textContent = locales['ui.send'] || 'Send';
        footerRight.textContent = locales['ui.back'] || 'Back';
    }
};

/** Selects a contact using the currently highlighted keypad navigation position. */
const handleSoftLeft = () => {
    if (currentView === 'contacts') {
        const contactIds = Object.keys(contactsData);
        if (contactIds.length === 0) return;

        const contact = contactsData[contactIds[selectedContactIndex]];
        showMessagesView(contact);
        post('getMessages', { contactId: contact.id });
        return;
    }

    sendMessage();
};

/** Closes the phone or returns from a conversation to the contact list. */
const handleSoftRight = () => {
    if (currentView === 'contacts') {
        post('close');
    } else {
        showContactsView();
    }
};

/** Sends the current Markdown message to the server contact callback. */
const sendMessage = () => {
    const message = messageInput.value.trim();

    if (!message || !currentContact) {
        playButtonSound('error');
        return;
    }

    playButtonSound('send');
    post('sendMessage', {
        contactId: currentContact.id,
        message
    });

    const messageEl = document.createElement('div');
    messageEl.className = 'message player';
    messageEl.innerHTML = renderMarkdown(message);
    messageHistory.appendChild(messageEl);
    messageHistory.scrollTop = messageHistory.scrollHeight;
    messageInput.value = '';
};

/** Adds a number-key character to the message input when a conversation is open. */
const handleNumberKey = (key) => {
    if (currentView !== 'messages') return;

    const start = messageInput.selectionStart;
    const end = messageInput.selectionEnd;
    const value = messageInput.value;

    messageInput.value = `${value.slice(0, start)}${key}${value.slice(end)}`;
    messageInput.selectionStart = messageInput.selectionEnd = start + key.length;
    messageInput.focus();
};

softLeftBtn.addEventListener('click', handleSoftLeft);
softRightBtn.addEventListener('click', handleSoftRight);

callLeftBtn.addEventListener('click', () => {
    if (currentView === 'contacts') {
        handleSoftLeft();
    } else {
        messageInput.focus();
    }
});

callRightBtn.addEventListener('click', () => {
    if (currentView === 'messages') {
        showContactsView();
    } else {
        post('close');
    }
});

messageInput.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey) {
        event.preventDefault();
        sendMessage();
    }
});

window.addEventListener('keyup', (event) => {
    if (event.key === 'Escape' && phoneOpen) {
        post('close');
    }
});

document.querySelectorAll('.num').forEach((button) => {
    button.addEventListener('click', () => handleNumberKey(button.dataset.key));
});

navUpBtn.addEventListener('click', () => navigateContacts(-1));
navDownBtn.addEventListener('click', () => navigateContacts(1));
bindButtonSounds();

/** Handles NUI state changes and incoming server messages. */
window.addEventListener('message', (event) => {
    const { action, ...data } = event.data;

    switch (action) {
        case 'setVisible':
            phoneOpen = Boolean(data.visible);
            phoneContainer.classList.toggle('hidden', !phoneOpen);

            if (phoneOpen) {
                popup.classList.remove('show');
            }
            break;
        case 'setVisible':
            phoneOpen = Boolean(data.visible);
            phoneContainer.classList.toggle('hidden', !phoneOpen);

            if (phoneOpen) {
                popup.classList.remove('show');
            }
            break;

        case 'setLocale': {
            const flatten = (obj, path = []) =>
                Object.entries(obj).reduce((acc, [key, value]) => {
                    const newPath = path.concat(key);
                    return typeof value === 'object' && value !== null
                        ? { ...acc, ...flatten(value, newPath) }
                        : { ...acc, [newPath.join('.')]: value };
                }, {});

            locales = flatten(data.locale);
            applyLocales();
            showContactsView();
            break;
        }

        case 'setContacts':
            contactsData = data.contacts || {};
            renderContacts(contactsData);
            break;

        case 'setMessages':
            if (currentContact && currentContact.id === data.contactId) {
                renderMessages(data.messages || []);
            }
            break;

        case 'messageResult':
            if (data.received === false) {
                appendMessageToHistory({
                    from: 'contact',
                    text: locales['groups.send_failed'] || 'Message could not be delivered. Check the FiveM server console for details.'
                }, true);
                playButtonSound('error');
            }
            break;

        case 'appendMessage': {
            const message = typeof data.message === 'string'
                ? { from: 'contact', text: data.message }
                : (data.message || { from: 'contact', text: '' });

            if (currentContact && currentContact.id === data.contactId) {
                appendMessageToHistory(message, true);
            } else {
                appendMessageToHistory(message, false);
            }

            if (!phoneOpen) {
                showIncomingPopup(data.contactId, message.text || '');
            }
            break;
        }

        case 'clearData':
            contactList.innerHTML = '';
            messageHistory.innerHTML = '';
            selectedContactIndex = 0;
            currentContact = null;

            if (data.clearContacts) {
                contactsData = {};
            }
            break;
    }
});

/** Adds one message to the conversation history and optionally scrolls to it. */
const normalizeMessageText = (value) => {
    if (value === null || value === undefined) return '';
    if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
        return String(value);
    }

    if (typeof value === 'object') {
        if (typeof value.text === 'string') return value.text;
        if (typeof value.message === 'string') return value.message;
        if (typeof value.content === 'string') return value.content;

        try {
            return JSON.stringify(value, null, 2);
        } catch (_) {
            return '';
        }
    }

    return String(value);
};

const appendMessageToHistory = (message, scroll) => {
    const normalized = typeof message === 'string'
        ? { from: 'contact', text: message }
        : (message && typeof message === 'object' ? message : { from: 'contact', text: String(message ?? '') });
    const messageEl = document.createElement('div');
    messageEl.className = `message ${normalized.from || 'contact'}`;
    messageEl.innerHTML = renderMarkdown(normalizeMessageText(normalized.text));
    messageHistory.appendChild(messageEl);

    if (scroll) {
        messageHistory.scrollTop = messageHistory.scrollHeight;
    }
};

/** Moves the selected contact up or down without using a polling loop. */
const navigateContacts = (direction) => {
    if (currentView !== 'contacts') return;

    const contactIds = Object.keys(contactsData);
    if (contactIds.length === 0) return;

    selectedContactIndex += direction;

    if (selectedContactIndex < 0) selectedContactIndex = contactIds.length - 1;
    if (selectedContactIndex >= contactIds.length) selectedContactIndex = 0;

    updateContactSelection();
};

/** Updates the title shown in the monochrome phone display. */
const updateScreenTitle = (title) => {
    screenTitle.textContent = title || '';
};

// --- MARKDOWN / MESSAGE FORMATTING ---

/** Converts the supported lightweight Markdown subset into safe HTML. */
const renderMarkdown = (value) => {
    let text = String(value ?? '').replace(/\r\n?/g, '\n');

    const escapeHtml = (s) => s
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');

    text = escapeHtml(text);

    const codeBlocks = [];
    text = text.replace(/```(?:[a-zA-Z0-9_-]+)?\n?([\s\S]*?)```/g, (_, code) => {
        const token = `@@CODEBLOCK${codeBlocks.length}@@`;
        codeBlocks.push(`<pre class="md-codeblock"><code>${code.replace(/\n$/, '')}</code></pre>`);
        return token;
    });

    const inlineCode = [];
    text = text.replace(/`([^`]+)`/g, (_, code) => {
        const token = `@@INLINECODE${inlineCode.length}@@`;
        inlineCode.push(`<code class="md-inline-code">${code}</code>`);
        return token;
    });

    const lines = text.split('\n');
    const out = [];
    let inList = null;

    const inline = (s) => s
        .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
        .replace(/__(.+?)__/g, '<strong>$1</strong>')
        .replace(/(?<!\*)\*([^*\n]+)\*(?!\*)/g, '<em>$1</em>')
        .replace(/(?<!_)_([^_\n]+)_(?!_)/g, '<em>$1</em>')
        .replace(/~~(.+?)~~/g, '<del>$1</del>');

    const closeList = () => {
        if (inList) {
            out.push(`</${inList}>`);
            inList = null;
        }
    };

    for (const line of lines) {
        if (/^@@CODEBLOCK\d+@@$/.test(line.trim())) {
            closeList();
            out.push(line.trim());
            continue;
        }

        let match = line.match(/^\s*[-*+]\s+(.+)$/);
        if (match) {
            if (inList !== 'ul') {
                closeList();
                out.push('<ul>');
                inList = 'ul';
            }
            out.push(`<li>${inline(match[1])}</li>`);
            continue;
        }

        match = line.match(/^\s*\d+\.\s+(.+)$/);
        if (match) {
            if (inList !== 'ol') {
                closeList();
                out.push('<ol>');
                inList = 'ol';
            }
            out.push(`<li>${inline(match[1])}</li>`);
            continue;
        }

        closeList();

        if (/^\s*---+\s*$/.test(line)) {
            out.push('<hr>');
            continue;
        }

        match = line.match(/^\s*(#{1,3})\s+(.+)$/);
        if (match) {
            const level = match[1].length;
            out.push(`<h${level}>${inline(match[2])}</h${level}>`);
            continue;
        }

        match = line.match(/^\s*>\s?(.*)$/);
        if (match) {
            out.push(`<blockquote>${inline(match[1])}</blockquote>`);
            continue;
        }

        out.push(line.trim() ? `<p>${inline(line)}</p>` : '<div class="md-spacer"></div>');
    }

    closeList();

    let result = out.join('');
    result = result.replace(/@@INLINECODE(\d+)@@/g, (_, i) => inlineCode[Number(i)]);
    result = result.replace(/@@CODEBLOCK(\d+)@@/g, (_, i) => codeBlocks[Number(i)]);
    return result;
};

/** Renders the available contacts and resets the selected row. */
const renderContacts = (contacts) => {
    contactList.innerHTML = '';
    const contactIds = Object.keys(contacts);

    noContacts.classList.toggle('hidden', contactIds.length > 0);
    if (contactIds.length === 0) return;

    contactIds.forEach((id) => {
        const contact = contacts[id];
        const li = document.createElement('li');
        li.textContent = contact.name;
        li.dataset.contactId = id;
        contactList.appendChild(li);
    });

    selectedContactIndex = Math.min(selectedContactIndex, contactIds.length - 1);
    updateContactSelection();
};

/** Applies the highlighted row to the contact list. */
const updateContactSelection = () => {
    document.querySelectorAll('#contact-list li').forEach((li, index) => {
        li.classList.toggle('selected', index === selectedContactIndex);

        if (index === selectedContactIndex) {
            li.scrollIntoView({ block: 'nearest' });
        }
    });
};

/** Renders the full conversation using the same Markdown formatter as live messages. */
const renderMessages = (messages) => {
    messageHistory.innerHTML = '';

    messages.forEach((message) => {
        appendMessageToHistory(message, false);
    });

    messageHistory.scrollTop = messageHistory.scrollHeight;
};
