// MIG4 display-only localization; never change domain data, JSON, commands or finding IDs.
(function () {
    'use strict';
    const dict = __MIG4_CATALOG_JSON__;
    const exact = dict.Exact;
    const statuses = dict.StatusWords;
    const patterns = dict.Patterns.map(row => [new RegExp(row.pattern), row.replacement]);
    const attributes = {
        'Toggle theme': 'Переключить тему',
        'Toggle Dark/Light Mode': 'Переключить светлую и тёмную тему',
        'Click for more info': 'Подробности проверки',
        'Keyboard Shortcuts (?)': 'Горячие клавиши (?)',
        'Show keyboard shortcuts and help': 'Показать горячие клавиши и справку',
        'Print report or save as PDF': 'Печать отчёта или сохранение в PDF',
        'Report navigation': 'Навигация по отчёту',
        'Report content': 'Содержимое отчёта',
        'Search findings... (press / to focus)': 'Поиск по результатам... (нажмите /)',
        'Type to filter findings by text content': 'Введите текст для фильтрации результатов',
        'Expand all cards and top priorities': 'Развернуть карточки и важнейшие действия',
        'Collapse all cards and top priorities': 'Свернуть карточки и важнейшие действия',
        'Expand/Collapse all objects': 'Развернуть или свернуть объекты',
        'Drag to resize the name column': 'Изменить ширину столбца названий',
        'Drag to reorder': 'Изменить порядок перетаскиванием',
        'Mark as completed': 'Отметить как выполненное',
        'Expand all finding cards': 'Развернуть все карточки',
        'Collapse all finding cards': 'Свернуть все карточки',
        'Toggle to show or hide findings marked as completed': 'Показать или скрыть выполненные результаты',
        'View controls': 'Управление отображением',
        'Card expansion controls': 'Разворачивание карточек',
        'Findings card view': 'Карточки результатов'
    };
    function translatedText(raw, context) {
        if (!raw || !raw.trim()) return raw;
        const core = raw.trim();
        let value = core;
        if (context === 'status') value = statuses[core] || core;
        else if (Object.prototype.hasOwnProperty.call(exact, core)) value = exact[core];
        else {
            const numbered = core.match(/^(\[\d+\/\d+\]) (.+)$/);
            if (numbered && exact[numbered[2]]) value = numbered[1] + ' ' + exact[numbered[2]];
            else for (const pair of patterns) {
                if (pair[0].test(core)) {
                    value = core.replace(pair[0], pair[1]);
                    break;
                }
            }
        }
        if (value === core) return raw;
        const pos = raw.indexOf(core);
        return raw.slice(0, pos) + value + raw.slice(pos + core.length);
    }
    function localizeNode(root) {
        if (!root || !root.querySelectorAll) return;
        const selector = [
            '.section-title', '.sidebar-title', '.sidebar .nav-item',
            '.finding-count', '.finding-item.finding-line',
            '.object-header > span:first-child', '.expand-collapse-btn',
            '.top-actions-title', '.top-action-section', '.top-action-details',
            '.top-action-fix', '.help-card-title', '.help-card-desc',
            '.help-section h3', '.shortcut-desc', '.print-toc-title'
        ].join(',');
        const textNodes = [];
        if (root.nodeType === 1 && root.matches && root.matches(selector)) textNodes.push(root);
        root.querySelectorAll(selector).forEach(el => textNodes.push(el));
        textNodes.forEach(el => el.childNodes.forEach(node => {
            if (node.nodeType !== 3 || !node.nodeValue.trim()) return;
            const value = translatedText(node.nodeValue, 'display');
            if (value !== node.nodeValue) node.nodeValue = value;
        }));
        const statusSelector = '.attr-value > span.finding, .attr-value > span.hint, .attr-value > span.secure';
        const statusNodes = [];
        if (root.nodeType === 1 && root.matches && root.matches(statusSelector)) statusNodes.push(root);
        root.querySelectorAll(statusSelector).forEach(el => statusNodes.push(el));
        statusNodes.forEach(el => {
            if (el.childElementCount) return;
            const value = translatedText(el.textContent, 'status');
            if (value !== el.textContent) el.textContent = value;
        });
        const labeled = [];
        if (root.nodeType === 1) labeled.push(root);
        root.querySelectorAll('[title],[aria-label],[placeholder]').forEach(el => labeled.push(el));
        labeled.forEach(el => ['title', 'aria-label', 'placeholder'].forEach(name => {
            const value = el.getAttribute && el.getAttribute(name);
            if (!value) return;
            const replacement = attributes[value] || exact[value];
            if (replacement && replacement !== value) el.setAttribute(name, replacement);
        }));
    }
    document.addEventListener('DOMContentLoaded', function () {
        localizeNode(document);
        // Dynamically constructed help/priority cards use the same visual catalog.
        const observer = new MutationObserver(records => records.forEach(rec =>
            rec.addedNodes.forEach(node => {
                if (node.nodeType === 1) localizeNode(node);
            })
        ));
        observer.observe(document.body, { childList: true, subtree: true });
    });
})();
