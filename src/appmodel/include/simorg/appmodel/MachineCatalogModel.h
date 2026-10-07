// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg
#pragma once

#include <QAbstractListModel>
#include <QJsonObject>
#include <QList>
#include <QObject>
#include <QString>
#include <QVariant>

namespace simorg::client {
class ServiceSession;
} // namespace simorg::client

namespace simorg::app {

struct AccessFieldOption
{
    QString value;
    QString label;
    QString description;
};

/**
 * One field of a permission's settings form, as the catalogue describes it.
 *
 * The service's `AccessField`. One level of nesting: a `RULE_LIST` field describes
 * the shape of one row in `fields`, and the catalogue never nests further, which
 * keeps the renderer a form rather than an interpreter.
 */
struct AccessField
{
    QString key;
    QString label;
    QString type;
    QString hint;
    QString placeholder;
    bool required = false;
    /** Invalid when unbounded. */
    QVariant minimum;
    QVariant maximum;
    QList<AccessFieldOption> options;
    QList<AccessField> fields;
    QString showWhenField;
    QString showWhenEquals;
    QString scope;
    QString format;
    QVariant defaultValue;

    static AccessField fromJson(const QJsonObject &json);
    /** The options' labels joined, for a one-line summary. */
    QString optionSummary() const;
    /** The label of the option holding `value`, or `value` itself for an option this build does not know. */
    QString labelForValue(const QString &value) const;
    /** Whether the field is shown for `record`, reading an unset sibling as its default. */
    bool appliesTo(const QVariantMap &record, const QList<AccessField> &siblings) const;
    /** Plain values for a QML delegate. */
    QVariantMap toVariant() const;
    bool inScope(const QString &wanted) const { return scope.isEmpty() || scope == wanted; }
};

/** A permission an agent can be asked for: the service's `AccessCategory`. */
struct AccessCategory
{
    QString key;
    QString label;
    QString description;
    QString deniedBehaviour;
    QString icon;
    QString sensitivity;
    QList<AccessField> fields;

    static AccessCategory fromJson(const QJsonObject &json);
};

/** The permissions, one row each, for the Access management screen. */
class AccessCategoryModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Role {
        KeyRole = Qt::UserRole + 1,
        LabelRole,
        DescriptionRole,
        DeniedBehaviourRole,
        IconRole,
        SensitivityRole,
        FieldCountRole,
        FieldsRole,
    };

    explicit AccessCategoryModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    const QList<AccessCategory> &categories() const { return m_items; }
    /** The category named `key`, or null. */
    const AccessCategory *find(const QString &key) const;
    void reset(const QList<AccessCategory> &categories);

    Q_INVOKABLE QVariantMap at(int row) const;

Q_SIGNALS:
    void countChanged();

private:
    QList<AccessCategory> m_items;
};

/**
 * The permissions this kind of machine can be asked for, as `MachineCatalog`.
 *
 * The service keeps a cached copy of the platform's catalogue and answers it
 * signed out (`GET /v1/machine/catalog`), so the screen draws before a session
 * exists. Read on every connection; `refresh` asks the service to read the
 * platform again.
 */
class MachineCatalogModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(simorg::app::AccessCategoryModel *accessCategories READ accessCategories CONSTANT)
    Q_PROPERTY(bool loading READ isLoading NOTIFY stateChanged)
    Q_PROPERTY(bool loaded READ isLoaded NOTIFY stateChanged)
    /** Why the list is missing or old. Empty when it is current. */
    Q_PROPERTY(QString lastError READ lastError NOTIFY stateChanged)

public:
    explicit MachineCatalogModel(client::ServiceSession *session, QObject *parent = nullptr);

    AccessCategoryModel *accessCategories() const { return m_categories; }
    bool isLoading() const { return m_loading > 0; }
    bool isLoaded() const { return m_loaded; }
    QString lastError() const { return m_lastError; }

    Q_INVOKABLE void refresh(const QString &machineCategoryKey = QStringLiteral("DESKTOP"));

Q_SIGNALS:
    void stateChanged();
    /** A new list was applied. */
    void applied();

private:
    void load(const QString &category, bool refresh);

    client::ServiceSession *m_session;
    AccessCategoryModel *m_categories;
    QString m_category = QStringLiteral("DESKTOP");
    int m_loading = 0;
    bool m_loaded = false;
    QString m_lastError;
};

} // namespace simorg::app
