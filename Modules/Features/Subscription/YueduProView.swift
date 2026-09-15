import SwiftUI

/// Pushed settings page describing `Yuedu Pro` status and its features.
///
/// `UserDetailView` opens it instead of the paywall once the user owns anything
/// (`ProEntryPolicy`), which makes it the one place a subscriber can restore,
/// reach Apple's subscription management, or start the lifetime upgrade. Those
/// actions sit above the feature list so they are visible without scrolling.
struct YueduProView: View {
    @EnvironmentObject private var store: SubscriptionStore
    @Environment(\.openURL) private var openURL
    @State private var showPaywall = false

    private let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")

    var body: some View {
        Form {
            statusSection
            manageSection
            featuresSection
        }
        .navigationTitle(localized("閱讀Pro"))
        .toolbarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .themedAppSurface(for: .settings)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
        .task { await store.loadProducts() }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        Section {
            HStack(spacing: DSSpacing.md) {
                Image(systemName: "crown.fill")
                    .font(DSFont.fixed(size: 28))
                    .foregroundStyle(DSColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("閱讀Pro"))
                        .font(DSFont.headline)
                    Text(statusDescription)
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary)
                }
                Spacer(minLength: 0)
                if store.isProActive {
                    Text(localized("已啟用"))
                        .font(DSFont.caption.weight(.semibold))
                        .foregroundStyle(DSColor.success)
                }
            }
            .padding(.vertical, DSSpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("pro_status_summary")
        }
        .interfaceSectionSurface()

        if let planActionTitle {
            Section {
                Button {
                    showPaywall = true
                } label: {
                    Text(planActionTitle)
                        .font(DSFont.bodyBold)
                        .foregroundStyle(DSColor.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DSSpacing.xs)
                }
                .listRowBackground(DSColor.accent)
                .accessibilityIdentifier("pro_status_plan_action")
            }
        }
    }

    private var statusDescription: String {
        if store.purchasedProductIDs.contains(SubscriptionStore.ProProduct.lifetime.rawValue) {
            return localized("你持有永久會員，所有 Pro 功能都已啟用")
        }
        return store.isProActive ? localized("已訂閱，感謝支持") : localized("解鎖高級個人化")
    }

    /// Follows the paywall's own state, so this page never offers a plan the
    /// paywall would not sell: nothing for a lifetime owner, the upgrade for a
    /// monthly subscriber, and the plans again if Pro lapses while the page is open.
    private var planActionTitle: String? {
        switch store.paywallPresentationState {
        case .offer:
            return localized("查看訂閱方案")
        case .upgradeFromMonthly:
            return localized("升級為永久會員")
        case .alreadyPro:
            return nil
        }
    }

    // MARK: - Manage

    private var manageSection: some View {
        Section {
            Button {
                Task { await store.restore() }
            } label: {
                HStack {
                    Label(localized("恢復購買"), systemImage: "arrow.clockwise")
                        .labelStyle(IconConsistentLabelStyle())
                    Spacer()
                    if store.isRestoring { ProgressView() }
                }
            }
            .disabled(store.isRestoring)
            .accessibilityIdentifier("pro_status_restore")

            if store.subscriptionManagement != .unavailable, let manageSubscriptionsURL {
                Button {
                    openURL(manageSubscriptionsURL)
                } label: {
                    Label(localized("管理訂閱"), systemImage: "gear")
                        .labelStyle(IconConsistentLabelStyle())
                }
                .accessibilityIdentifier("pro_status_manage_subscription")
            }
        } footer: {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                if store.subscriptionManagement == .monthlyAlongsideLifetime {
                    Text(localized("升級後請記得取消月訂閱，否則會繼續扣款"))
                        .dsSectionFooter()
                }
                if let error = store.lastErrorMessage {
                    Text(error)
                        .dsSectionFooter(color: DSColor.destructive)
                }
            }
        }
        .interfaceSectionSurface()
    }

    // MARK: - Features

    private var featuresSection: some View {
        Section(header: Text(localized("Pro 功能"))) {
            ForEach(PremiumFeature.marketedFeatures()) { feature in
                HStack(spacing: DSSpacing.md) {
                    Image(systemName: feature.iconName)
                        .font(DSFont.fixed(size: 17, weight: .medium))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(DSColor.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.localizedTitle)
                            .foregroundColor(DSColor.textPrimary)
                        Text(feature.localizedSubtitle)
                            .font(DSFont.caption)
                            .foregroundColor(DSColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: store.hasAccess(feature) ? "checkmark.circle.fill" : "lock.fill")
                        .foregroundStyle(store.hasAccess(feature) ? DSColor.success : DSColor.textSecondary)
                        .accessibilityLabel(store.hasAccess(feature) ? localized("已解鎖") : localized("需要 Pro"))
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
        .interfaceSectionSurface()
    }
}

#Preview {
    NavigationStack {
        YueduProView()
            .environmentObject(SubscriptionStore.shared)
    }
}
