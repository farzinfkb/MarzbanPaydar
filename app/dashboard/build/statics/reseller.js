(function() {
    var TRASH_PATH_PREFIX = "M14.74 9l-.346 9";  // start of the delete-icon SVG path

    function detectRole() {
        try {
            var token = localStorage.getItem('token');
            if (!token) {
                document.body.removeAttribute('data-role');
                return;
            }
            var payload = JSON.parse(atob(token.split('.')[1]));
            if (payload && payload.access !== 'sudo') {
                document.body.setAttribute('data-role', 'reseller');
            } else {
                document.body.removeAttribute('data-role');
            }
        } catch(e) {}
    }

    function markButtons() {
        if (document.body.getAttribute('data-role') !== 'reseller') return;

        // Reset Usage: match by exact button text
        document.querySelectorAll('button').forEach(function(b) {
            var t = (b.textContent || '').trim();
            if (t === 'Reset Usage' || t === 'ریست مصرف' || t === 'Сброс использования' || t === '重置使用') {
                b.classList.add('reseller-hidden');
            }
        });

        // Delete: match by the trash SVG path inside the button
        document.querySelectorAll('button svg path').forEach(function(p) {
            var d = p.getAttribute('d') || '';
            if (d.indexOf(TRASH_PATH_PREFIX) === 0) {
                var btn = p.closest('button');
                if (btn) btn.classList.add('reseller-hidden');
            }
        });
    }

    function tick() {
        detectRole();
        markButtons();
    }

    // Initial run once DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', tick);
    } else {
        tick();
    }

    // Re-run whenever the DOM changes (modals open/close, route changes)
    new MutationObserver(tick).observe(document.documentElement, {
        subtree: true, childList: true
    });

    // Re-run on login/logout
    window.addEventListener('storage', tick);
})();
