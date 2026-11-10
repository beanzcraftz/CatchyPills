#include "ITSMController.hpp"

#include <QClipboard>
#include <QGuiApplication>
#include <QProcess>

namespace catchypills::itsm {

ITSMController::ITSMController(QObject *parent)
    : QObject(parent)
{
}

void ITSMController::generatePrompt(const QString &templateName, const QString &rawContent)
{
    const QString cleanTemplate = templateName.trimmed();
    if (cleanTemplate.isEmpty()) {
        return;
    }

    const QString prompt = QStringLiteral("Update this article to use the %1 template- \n\n%2")
                               .arg(cleanTemplate, rawContent);

    if (QClipboard *clipboard = QGuiApplication::clipboard()) {
        clipboard->setText(prompt);
    }

    if (m_lastTemplateName != cleanTemplate) {
        m_lastTemplateName = cleanTemplate;
        Q_EMIT lastTemplateNameChanged();
    }

    QProcess::startDetached(
        QStringLiteral("notify-send"),
        {QStringLiteral("-a"),
         QStringLiteral("CatchyPills ITSM"),
         QStringLiteral("ITSM Prompt Copied"),
         QStringLiteral("Copied prompt for %1 (%2 chars)")
             .arg(cleanTemplate)
             .arg(rawContent.size())});
}

} // namespace catchypills::itsm
