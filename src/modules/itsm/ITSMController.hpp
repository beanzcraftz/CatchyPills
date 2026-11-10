#pragma once

#include <QObject>
#include <QString>

namespace catchypills::itsm {

/**
 * Formats ServiceNow KB article template refactoring prompts from user-provided
 * raw content directly onto the Wayland clipboard with desktop notifications.
 */
class ITSMController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString lastTemplateName READ lastTemplateName NOTIFY lastTemplateNameChanged)

public:
    explicit ITSMController(QObject *parent = nullptr);

    QString lastTemplateName() const { return m_lastTemplateName; }

    Q_INVOKABLE void generatePrompt(const QString &templateName, const QString &rawContent);

Q_SIGNALS:
    void lastTemplateNameChanged();

private:
    QString m_lastTemplateName;
};

} // namespace catchypills::itsm
