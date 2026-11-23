#!/usr/bin/env python3
"""MIG11: localized dynamic browser strings from the 2026-11-23 MIG10 report.
Presentation-only: preserves finding definitions, AD values, scoring, JSON and licensing.
"""
import argparse
import hashlib
import json
from pathlib import Path

ENC = 'utf-8-sig'
RENDER_JS = 'src/modules/Reporting/templates/report-scripts.js'
FINDINGS = 'src/modules/Core/adPEAS-FindingDefinitions.ps1'

def only(s, before, after, where, expected=1):
    count = s.count(before)
    if count != expected:
        raise ValueError('MIG11 source witness ' + where + ': expected ' + str(expected) + ', got ' + str(count))
    return s.replace(before, after)

def scoped(s, start, stop, changes, where):
    a = s.index(start)
    b = s.index(stop, a + len(start))
    segment = s[a:b]
    for before, after in changes:
        segment = only(segment, before, after, where + ': ' + before[:45])
    return s[:a] + segment + s[b:]

def build(candidate):
    path = candidate / RENDER_JS
    s = path.read_text(encoding=ENC)
    definitions = candidate / FINDINGS
    sha = hashlib.sha256(definitions.read_bytes()).hexdigest()
    s = scoped(s, 'function updateExtendedAttrCounters(movedElement) {',
        '//  PRINT / PDF PREPARATION', [
        ("const prefix = currentText.startsWith('Hide') ? 'Hide' : 'Show';",
         "const prefix = toggleBtn.classList.contains('expanded') ? 'Скрыть дополнительные атрибуты: ' : 'Показать дополнительные атрибуты: ';"),
        ("textSpan.textContent = prefix + ' ' + extCount + ' more attribute(s)';",
         "textSpan.textContent = prefix + extCount;")
    ], 'drag-drop')
    s = only(s,
        'Example commands for reference only. Always test in a non-production environment first and adapt to your specific situation.',
        'Команды приведены только для примера. Перед применением обязательно проверьте их в непроизводственной среде и адаптируйте к своей конфигурации.',
        'remediation warning')
    s = only(s, '>Copy</button>', '>Копировать</button>', 'copy button')
    s = scoped(s, 'function copyToClipboard(button, text) {',
        '// Per-card name column resizing', [
        ("button.textContent = 'Copied!';", "button.textContent = 'Скопировано';"),
        ("button.textContent = 'Failed';", "button.textContent = 'Ошибка';"),
        ("button.textContent = 'Copy';", "button.textContent = 'Копировать';")
    ], 'copy status')
    s = scoped(s, 'function toggleTheme() {', 'function updateThemeUI(theme) {', [
        ("announceToScreenReader('Theme changed to ' + newTheme + ' mode');",
         "announceToScreenReader('Тема изменена: ' + (newTheme === 'dark' ? 'тёмная' : 'светлая'));")
    ], 'theme announcement')
    s = scoped(s, 'function filterBySeverity(severity) {', 'function filterByCategory(category) {', [
        ("const severityLabel = severity === 'all' ? 'all severities' : severity;",
         "const severityLabel = ({all: 'все уровни важности', finding: 'нарушения', hint: 'предупреждения', note: 'сведения', secure: 'безопасно'})[severity] || severity;"),
        ("announceToScreenReader('Filtered by ' + severityLabel + '. ' + count + ' findings shown.');",
         "announceToScreenReader('Фильтр по важности: ' + severityLabel + '. Показано карточек: ' + count + '.');")
    ], 'severity announcement')
    s = scoped(s, 'function filterByCategory(category) {', 'function updateItemCount(', [
        ("announceToScreenReader('Filtered by category ' + category + '. ' + count + ' findings shown.');",
         "const categoryLabel = ({all: 'все категории', domain: 'домен', creds: 'учётные данные', rights: 'права', delegation: 'делегирование', adcs: 'службы сертификатов AD CS', accounts: 'учётные записи', gpo: 'групповые политики', computer: 'компьютеры', application: 'приложения', shares: 'общие ресурсы', bloodhound: 'BloodHound'})[category] || category;\n            announceToScreenReader('Фильтр по категории: ' + categoryLabel + '. Показано карточек: ' + count + '.');")
    ], 'category announcement')
    s = scoped(s, 'function toggleHideCompleted() {', '// KEYBOARD SHORTCUTS', [
        ("'Completed findings hidden. ' + visibleCount + ' findings visible.'",
         "'Выполненные проверки скрыты. Видимых карточек: ' + visibleCount + '.'"),
        ("'Showing all findings including completed. ' + visibleCount + ' findings visible.'",
         "'Показаны все проверки, включая выполненные. Видимых карточек: ' + visibleCount + '.'")
    ], 'completed announcement')
    s = scoped(s, 'function clearAdPEASData() {', 'function toggleShortcutHelp() {', [
        ("'No adPEAS data found in storage.'", "'В хранилище браузера нет данных adPEAS.'"),
        ("'No adPEAS data found in browser storage.'", "'В хранилище браузера нет сохранённых данных adPEAS.'"),
        ("'This will remove all adPEAS data from your browser:\\n\\n'",
         "'Будут удалены все данные adPEAS из этого браузера:\\n\\n'"),
        ("'• Completed findings (checkboxes) for ALL reports\\n'",
         "'• Отметки выполнения во ВСЕХ отчётах\\n'"),
        ("'• Theme preference\\n\\n'", "'• Предпочтение темы оформления\\n\\n'"),
        ("'Found ' + count + ' stored item(s).\\n\\n'",
         "'Найдено сохранённых элементов: ' + count + '.\\n\\n'"),
        ("'The page will reload after clearing. Continue?'",
         "'После очистки страница перезагрузится. Продолжить?'"),
        ("'All adPEAS data cleared. Reloading page.'",
         "'Все сохранённые данные adPEAS очищены. Страница перезагружается.'")
    ], 'localStorage dialog')
    s = scoped(s, 'function toggleShortcutHelp() {', 'function hideShortcutHelp() {', [
        ("'Help dialog opened. Press Escape to close.'",
         "'Открыта справка. Для закрытия нажмите Escape.'")
    ], 'help announcement')
    s = scoped(s, 'function buildPrintTOC() {', '// Register print event handlers', [
        ("tocTitle.textContent = 'Table of Contents';", "tocTitle.textContent = 'Оглавление отчёта';"),
        ("['Section', 'Findings', 'Hints', 'Notes', 'Secure']",
         "['Раздел', 'Нарушения', 'Предупреждения', 'Сведения', 'Безопасно']"),
        ("totalLabel.textContent = 'Total';", "totalLabel.textContent = 'Итого';")
    ], 'print TOC')
    s = only(s, "'Unknown Finding'", "'Неизвестная находка'", 'fallback finding', expected=2)
    s = only(s, " || 'Unknown'", " || 'Неизвестно'", 'fallback category', expected=2)
    s = scoped(s, 'function formatScoreBreakdown(breakdown) {',
        '// Format score breakdown as styled HTML tooltip content', [
        ("return 'No risk score (informational)';",
         "return 'Оценка риска отсутствует (информационный результат)';"),
        ("lines.push('Score Breakdown:');", "lines.push('Состав оценки риска:');"),
        ("lines.push('Base: ' +", "lines.push('Базовая оценка: ' +"),
        ("lines.push('Impact: ×' +", "lines.push('Последствия: ×' +"),
        ("lines.push('Exploitability: ×' +", "lines.push('Возможность эксплуатации: ×' +"),
        ("lines.push('Security: ×' +", "lines.push('Защитные меры: ×' +"),
        ("lines.push('Correlation: +' +", "lines.push('Взаимосвязи: +' +"),
        ("lines.push('Final: ' +", "lines.push('Итоговая оценка: ' +"),
        ("' (' + breakdown.impactReason + ')'",
         "' (' + translateMIG9ScoreReason(breakdown.impactReason) + ')'"),
        ("breakdown.exploitReasons.join(', ')",
         "breakdown.exploitReasons.map(translateMIG9ScoreReason).join(', ')"),
        ("breakdown.securityReasons.join(', ')",
         "breakdown.securityReasons.map(translateMIG9ScoreReason).join(', ')"),
        ("' (' + breakdown.correlationReason + ')'",
         "' (' + translateMIG9ScoreReason(breakdown.correlationReason) + ')'")
    ], 'plain-text score')
    path.write_text(s, encoding=ENC)
    if sha != hashlib.sha256(definitions.read_bytes()).hexdigest():
        raise ValueError('Original finding catalog changed')
    return dict(Schema='adPEAS-RU.2.11.0.MIG11.1',
                Source='real AD-Audit-MIG10.html, 2026-11-23',
                CanonicalFindingDefinitionsPreserved=True,
                ExtendedAttributeCountPreserved=True,
                AdDataModified=False, RiskScoringModified=False,
                JsonExportModified=False, LicenseRulesModified=False,
                ProductionReady=False, RealAdRuntimeVerifiedByCI=False,
                OriginalDefinitionsSha256=sha)

def main():
    a = argparse.ArgumentParser()
    a.add_argument('--candidate', type=Path, required=True)
    a.add_argument('--report', type=Path, required=True)
    args = a.parse_args()
    result = build(args.candidate)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding=ENC)
    print('MIG11 PASS: dynamic UI and print/local-storage labels translated')

if __name__ == '__main__':
    main()
