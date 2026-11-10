#include "ITSMController.hpp"

#include <QClipboard>
#include <QGuiApplication>
#include <QProcess>

namespace catchypills::itsm {

ITSMController::ITSMController(QObject *parent)
    : QObject(parent)
{
}

void ITSMController::setHtmlReady(const QString &htmlText)
{
    if (htmlText.trimmed().isEmpty()) {
        return;
    }

    // Ignore our own generated prompt bouncing back through ext-data-control-v1.
    if (htmlText == m_lastGeneratedPrompt
        || htmlText.startsWith(QStringLiteral("Update this article to use the "))) {
        return;
    }

    if (m_storedHtml != htmlText) {
        m_storedHtml = htmlText;
        Q_EMIT storedHtmlChanged();
    }

    if (!m_isHtmlReady) {
        m_isHtmlReady = true;
        Q_EMIT isHtmlReadyChanged();
    }
}

void ITSMController::clearReady()
{
    if (m_isHtmlReady) {
        m_isHtmlReady = false;
        Q_EMIT isHtmlReadyChanged();
    }
}

void ITSMController::generatePrompt(const QString &templateName)
{
    const QString cleanTemplate = templateName.trimmed();
    if (cleanTemplate.isEmpty()) {
        return;
    }

    const QString prompt = QStringLiteral("Update this article to use the %1 template- \n\n%2")
                               .arg(cleanTemplate, m_storedHtml);

    m_lastGeneratedPrompt = prompt;
    if (QClipboard *clipboard = QGuiApplication::clipboard()) {
        clipboard->setText(prompt);
    }

    if (m_lastTemplateName != cleanTemplate) {
        m_lastTemplateName = cleanTemplate;
        Q_EMIT lastTemplateNameChanged();
    }

    if (m_isHtmlReady) {
        m_isHtmlReady = false;
        Q_EMIT isHtmlReadyChanged();
    }

    QProcess::startDetached(
        QStringLiteral("notify-send"),
        {QStringLiteral("-a"),
         QStringLiteral("CatchyPills ITSM"),
         QStringLiteral("ITSM Prompt Copied"),
         QStringLiteral("Copied prompt for %1 (%2 chars source HTML)")
             .arg(cleanTemplate)
             .arg(m_storedHtml.size())});
}

} // namespace catchypills::itsm
