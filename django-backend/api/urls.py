from django.urls import path, include
from rest_framework.routers import DefaultRouter
from . import views
from . import views_auth
from . import views_construction
from . import views_site_engineer
from . import views_time_validation
from . import views_material
from . import views_accountant_documents
from . import views_labor_mismatch
from . import views_admin
from . import views_budget
from . import views_budget_management
from . import views_export
from . import views_client
from . import views_notifications
from . import views_catalogue
from . import views_location
from . import views_cash_and_salary

# Import old working ViewSets
from .views_working_old import (
    RoleViewSet, UserViewSet, SiteViewSet, MaterialMasterViewSet,
    DailySiteReportViewSet, DailyLabourSummaryViewSet, DailySalaryEntryViewSet,
    DailyMaterialBalanceViewSet, MaterialBillViewSet, WorkActivityViewSet,
    NotificationViewSet, ComplaintViewSet, ComplaintActionViewSet,
    AuditLogViewSet, AdminRoleChangeLogViewSet,
    health_check, database_health
)

# Router for old CRUD endpoints
router = DefaultRouter()
router.register(r'roles', RoleViewSet, basename='role')
router.register(r'users', UserViewSet, basename='user')
router.register(r'sites', SiteViewSet, basename='site')
router.register(r'materials', MaterialMasterViewSet, basename='material')
router.register(r'daily-reports', DailySiteReportViewSet, basename='daily-report')
router.register(r'labour-summary', DailyLabourSummaryViewSet, basename='labour-summary')
router.register(r'salary-entries', DailySalaryEntryViewSet, basename='salary-entry')
router.register(r'material-balance', DailyMaterialBalanceViewSet, basename='material-balance')
router.register(r'material-bills', MaterialBillViewSet, basename='material-bill')
router.register(r'work-activities', WorkActivityViewSet, basename='work-activity')
router.register(r'notifications', NotificationViewSet, basename='notification')
router.register(r'complaints', ComplaintViewSet, basename='complaint')
router.register(r'complaint-actions', ComplaintActionViewSet, basename='complaint-action')
router.register(r'audit-logs', AuditLogViewSet, basename='audit-log')
router.register(r'role-change-logs', AdminRoleChangeLogViewSet, basename='role-change-log')

urlpatterns = [
    # Health checks
    path('health/', health_check, name='health'),
    path('health/db/', database_health, name='database-health'),
    
    # ============================================
    # CUSTOM AUTHENTICATION ENDPOINTS
    # ============================================
    path('auth/register/', views_auth.register, name='register'),
    path('auth/login/', views_auth.login, name='login'),
    path('auth/status/', views_auth.check_approval_status, name='check-status'),
    path('auth/roles/', views_auth.get_roles, name='get-roles'),
    
    # Admin endpoints - User Management
    path('admin/pending-users/', views_auth.get_pending_users, name='pending-users'),
    path('admin/all-users/', views_auth.get_all_users, name='all-users'),
    path('admin/approve-user/<uuid:user_id>/', views_auth.approve_user, name='approve-user'),
    path('admin/reject-user/<uuid:user_id>/', views_auth.reject_user, name='reject-user'),
    path('admin/create-user/', views_auth.admin_create_user, name='admin-create-user'),
    path('admin/create-admin/', views_auth.admin_create_admin, name='admin-create-admin'),
    path('admin/create-role/', views_auth.admin_create_role, name='admin-create-role'),
    path('admin/roles/', views_auth.get_all_roles, name='admin-get-roles'),
    
    # ============================================
    # CLIENT APIS
    # ============================================
    # CLIENT DASHBOARD APIs
    # ============================================
    path('client/sites/', views_auth.get_client_sites, name='client-get-sites'),
    path('client/site-details/', views_client.get_client_site_details, name='client-site-details'),
    path('client/labour-summary/', views_client.get_client_labour_summary, name='client-labour-summary'),
    path('client/photos/', views_client.get_client_photos, name='client-photos'),
    path('client/photos-by-date/', views_client.get_client_photos_by_date, name='client-photos-by-date'),
    path('client/documents/', views_client.get_client_documents, name='client-documents'),
    path('client/materials/', views_client.get_client_materials, name='client-materials'),
    path('client/complaints/', views_client.get_client_complaints, name='client-get-complaints'),
    path('client/complaints/create/', views_client.create_client_complaint, name='client-create-complaint'),
    path('client/complaints/<uuid:complaint_id>/messages/', views_client.get_complaint_messages, name='client-get-complaint-messages'),
    path('client/complaints/<uuid:complaint_id>/messages/send/', views_client.send_complaint_message, name='client-send-complaint-message'),
    
    # Admin Site Dashboard
    path('admin/sites/<str:site_id>/dashboard/', views_admin.get_site_dashboard, name='site-dashboard'),
    
    # ============================================
    # ADMIN ENHANCED FEATURES
    # ============================================
    # Site Selection & Metrics
    path('admin/sites/', views_admin.get_all_sites, name='admin-sites'),
    path('admin/sites/<str:site_id>/metrics/', views_admin.get_site_metrics, name='site-metrics'),
    path('admin/sites/<str:site_id>/metrics/update/', views_admin.update_site_metrics, name='update-site-metrics'),
    
    # Specialized Logins
    path('admin/specialized-login/', views_admin.specialized_login, name='specialized-login'),
    
    # Labour Count View
    path('admin/sites/<str:site_id>/labour-count/', views_admin.get_labour_count_data, name='labour-count-data'),
    
    # Bills View
    path('admin/sites/<str:site_id>/bills/', views_admin.get_bills_data, name='bills-data'),
    
    # Full Accounts (P/L)
    path('admin/sites/<str:site_id>/profit-loss/', views_admin.get_profit_loss_data, name='profit-loss-data'),
    
    # Work Notifications
    path('admin/notifications/', views_admin.get_work_notifications, name='work-notifications'),
    path('admin/notifications/<int:notification_id>/read/', views_admin.mark_notification_read, name='mark-notification-read'),
    
    # Late Entry Notifications (New System)
    path('notifications/late-entry/', views_notifications.create_late_entry_notification, name='create-late-entry-notification'),
    path('notifications/register-device/', views_notifications.register_device_token, name='register-device-token'),
    path('notifications/guest-checkin/', views_notifications.guest_checkin_notification, name='guest-checkin-notification'),
    path('notifications/guest-checkins/', views_notifications.get_guest_checkins, name='get-guest-checkins'),

    # Guest catalogue (public list for the guest app + admin management)
    path('catalogue/', views_catalogue.list_catalogue, name='catalogue-list'),
    path('admin/catalogue/', views_catalogue.admin_catalogue, name='admin-catalogue'),
    path('admin/catalogue/<uuid:item_id>/', views_catalogue.admin_catalogue_item, name='admin-catalogue-item'),

    # Supervisor live location (working hours only; admins view latest position)
    path('location/update/', views_location.update_location, name='location-update'),
    path('location/status/', views_location.report_sharing_status, name='location-status'),
    path('admin/supervisor-locations/', views_location.admin_supervisor_locations, name='admin-supervisor-locations'),
    path('notifications/mark-all-read/', views_notifications.mark_all_notifications_read, name='mark-all-notifications-read'),
    path('notifications/', views_notifications.get_notifications, name='get-notifications'),
    path('notifications/<uuid:notification_id>/read/', views_notifications.mark_notification_read, name='mark-late-notification-read'),
    
    # Material Purchases
    path('admin/sites/<str:site_id>/material-purchases/', views_admin.get_total_material_purchases, name='material-purchases'),
    
    # Site Documents
    path('admin/sites/<str:site_id>/documents/', views_admin.get_site_documents, name='site-documents'),
    path('admin/sites/<str:site_id>/documents/upload/', views_admin.upload_site_document, name='upload-site-document'),
    
    # Site Comparison
    path('admin/sites/compare/', views_admin.compare_sites, name='compare-sites'),
    
    # ============================================
    # BUDGET MANAGEMENT & REAL-TIME VISIBILITY
    # ============================================
    # Budget Management
    path('admin/sites/budget/set/', views_budget.set_budget, name='set-budget'),
    path('admin/sites/<int:site_id>/budget/', views_budget.get_budget, name='get-budget'),
    path('admin/sites/<int:site_id>/budget/utilization/', views_budget.get_budget_utilization, name='get-budget-utilization'),
    path('admin/budgets/all/', views_budget.get_all_sites_budgets, name='get-all-sites-budgets'),
    
    # Real-time Updates
    path('admin/realtime-updates/', views_budget.get_realtime_updates, name='get-realtime-updates'),
    
    # Audit Trail
    path('admin/sites/<int:site_id>/audit-trail/', views_budget.get_audit_trail, name='get-audit-trail'),
    
    # ============================================
    # CONSTRUCTION MANAGEMENT ENDPOINTS
    # ============================================
    # Common endpoints (all roles)
    path('construction/create-site/', views_construction.create_site, name='create-site'),
    path('construction/create-area/', views_construction.create_area, name='create-area'),
    path('construction/create-street/', views_construction.create_street, name='create-street'),
    path('construction/areas/', views_construction.get_areas, name='get-areas'),
    path('construction/streets/<str:area>/', views_construction.get_streets, name='get-streets'),
    path('construction/sites/', views_construction.get_sites, name='get-sites'),
    path('construction/materials/', views_construction.get_materials, name='get-materials'),
    path('construction/materials/add/', views_construction.add_material, name='add-material'),
    
    # Time validation endpoints
    path('construction/validate-entry-time/', views_time_validation.validate_entry_time, name='validate-entry-time'),
    path('construction/current-ist-time/', views_time_validation.get_current_ist_time, name='current-ist-time'),
    
    # Supervisor endpoints
    path('construction/labour/', views_construction.submit_labour_count, name='submit-labour'),
    path('construction/check-entry-lock/', views_construction.check_entry_lock, name='check-entry-lock'),
    path('construction/test-material/', views_construction.test_material_balance, name='test-material-balance'),
    path('construction/submit-material-balance/', views_construction.submit_material_balance, name='submit-material-balance'),
    path('construction/today-entries/', views_construction.get_today_entries, name='get-today-entries'),
    path('construction/today-entries-supervisor/', views_construction.get_today_entries_for_supervisor, name='get-today-entries-supervisor'),
    path('construction/aggregated-today-entries/', views_construction.get_aggregated_today_entries, name='get-aggregated-today-entries'),
    path('construction/entries-by-date/', views_construction.get_entries_by_date, name='get-entries-by-date'),
    path('construction/upload-images/', views_construction.upload_site_images, name='upload-images'),
    path('construction/supervisor/history/', views_construction.get_supervisor_history, name='supervisor-history'),
    path('construction/history-by-day/', views_construction.get_history_by_day, name='history-by-day'),
    
    # Accountant endpoints
    path('construction/accountant/all-entries/', views_construction.get_all_entries_for_accountant, name='accountant-all-entries'),
    path('construction/accountant/all-photos/', views_construction.get_all_site_photos_for_accountant, name='accountant-all-photos'),
    path('accountant/add-client-requirement/', views_construction.add_client_requirement, name='add-client-requirement'),
    path('accountant/update-client-requirement/<uuid:requirement_id>/', views_construction.update_client_requirement, name='update-client-requirement'),
    path('admin/client-requirements/', views_construction.get_client_requirements, name='get-client-requirements'),
    
    # ============================================
    # SITE ENGINEER ENDPOINTS
    # ============================================
    path('engineer/sites/', views_site_engineer.get_assigned_sites, name='engineer-sites'),
    path('engineer/daily-status/<uuid:site_id>/', views_site_engineer.get_daily_status, name='engineer-daily-status'),
    path('engineer/work-activity/', views_site_engineer.upload_work_activity, name='engineer-work-activity'),
    path('engineer/complaints/<uuid:site_id>/', views_site_engineer.get_complaints, name='engineer-complaints'),
    path('engineer/complaint-action/', views_site_engineer.upload_complaint_rectification, name='engineer-complaint-action'),
    path('engineer/extra-work/', views_site_engineer.submit_extra_work, name='engineer-extra-work'),
    path('engineer/project-files/<uuid:site_id>/', views_site_engineer.get_project_files, name='engineer-project-files'),
    
    # Change Request System
    path('construction/request-change/', views_construction.request_change, name='request-change'),
    path('construction/my-change-requests/', views_construction.get_my_change_requests, name='my-change-requests'),
    path('construction/pending-change-requests/', views_construction.get_pending_change_requests, name='pending-change-requests'),
    path('construction/handle-change-request/<uuid:request_id>/', views_construction.handle_change_request, name='handle-change-request'),
    path('construction/modified-entries/', views_construction.get_modified_entries, name='modified-entries'),
    path('construction/entries-by-date-role/', views_construction.get_entries_by_date_and_role, name='entries-by-date-role'),
    path('construction/approved-entries/', views_construction.get_approved_entries, name='approved-entries'),

    # Cash Entries (Accountant)
    path('construction/confirm-cash-entry/', views_construction.confirm_cash_entry, name='confirm-cash-entry'),
    path('construction/create-custom-cash-entry/', views_construction.create_custom_cash_entry, name='create-custom-cash-entry'),
    path('construction/check-cash-entry/', views_construction.check_cash_entry_exists, name='check-cash-entry'),
    
    # Cash Entries Management
    path('construction/cash-entries/', views_cash_and_salary.get_cash_entries, name='get-cash-entries'),
    path('construction/cash-entries/summary/', views_cash_and_salary.get_cash_entries_summary, name='get-cash-entries-summary'),
    
    # Site Engineer Photo Upload
    path('construction/upload-site-photo/', views_construction.upload_site_photo, name='upload-site-photo'),
    path('construction/site-photos/<uuid:site_id>/', views_construction.get_site_photos, name='get-site-photos'),
    path('construction/today-upload-status/<uuid:site_id>/', views_construction.get_today_upload_status, name='today-upload-status'),
    
    # Supervisor Photo Upload
    path('construction/supervisor-upload-photos/', views_construction.supervisor_upload_photos, name='supervisor-upload-photos'),
    path('construction/supervisor-photos/', views_construction.get_supervisor_photos, name='get-supervisor-photos'),
    path('construction/supervisor-photos-for-accountant/', views_construction.get_supervisor_photos_for_accountant, name='get-supervisor-photos-for-accountant'),
    
    # Working Sites (Accountant assigns to Supervisor)
    path('construction/assign-working-sites/', views_construction.assign_working_sites, name='assign-working-sites'),
    path('construction/working-sites/', views_construction.get_working_sites, name='get-working-sites'),
    path('construction/clear-working-sites/', views_construction.clear_working_sites, name='clear-working-sites'),
    path('construction/accountant-working-sites-count/', views_construction.get_accountant_working_sites_count, name='accountant-working-sites-count'),
    path('construction/admin/all-working-sites/', views_construction.get_all_working_sites, name='get-all-working-sites'),
    path('construction/today-sites-with-data/', views_construction.get_today_sites_with_data, name='get-today-sites-with-data'),
    path('construction/total-counts/', views_construction.get_total_counts, name='get-total-counts'),
    path('construction/supervisors-list/', views_construction.get_supervisors_list, name='get-supervisors-list'),
    path('construction/all-sites/', views_construction.get_all_sites, name='get-all-sites'),
    
    # Extra Cost
    path('construction/submit-extra-cost/', views_construction.submit_extra_cost, name='submit-extra-cost'),
    path('construction/extra-costs/<uuid:site_id>/', views_construction.get_extra_costs, name='get-extra-costs'),
    
    # Architect APIs
    path('construction/upload-architect-document/', views_construction.upload_architect_document, name='upload-architect-document'),
    path('construction/upload-architect-complaint/', views_construction.upload_architect_complaint, name='upload-architect-complaint'),
    path('construction/architect-documents/', views_construction.get_architect_documents, name='get-architect-documents'),
    path('construction/architect-complaints/', views_construction.get_architect_complaints, name='get-architect-complaints'),
    path('construction/architect-history/', views_construction.get_architect_history, name='get-architect-history'),
    path('construction/upload-project-file/', views_construction.upload_project_file, name='upload-project-file'),
    path('construction/project-files/<uuid:site_id>/', views_construction.get_project_files, name='get-project-files'),
    path('construction/client-complaints/', views_construction.get_client_complaints_for_architect, name='get-client-complaints-architect'),
    path('construction/complaints/<uuid:complaint_id>/messages/', views_construction.get_complaint_messages_architect, name='get-complaint-messages-architect'),
    path('construction/complaints/<uuid:complaint_id>/messages/send/', views_construction.send_complaint_message_architect, name='send-complaint-message-architect'),
    path('construction/raise-complaint/', views_construction.raise_complaint, name='raise-complaint'),
    path('construction/complaints/', views_construction.get_complaints, name='get-complaints'),
    
    # Material Requirements System
    path('construction/material-requirements/', views_construction.submit_material_requirement, name='submit-material-requirement'),
    path('construction/material-requirements/list/', views_construction.get_material_requirements, name='get-material-requirements'),
    path('construction/material-requirements/<uuid:requirement_id>/status/', views_construction.update_material_requirement_status, name='update-material-requirement-status'),
    path('construction/material-requirements/<uuid:requirement_id>/delete/', views_construction.delete_material_requirement, name='delete-material-requirement'),
    
    # Site Engineer Document APIs
    path('construction/upload-site-engineer-document/', views_construction.upload_site_engineer_document, name='upload-site-engineer-document'),
    path('construction/site-engineer-documents/', views_construction.get_site_engineer_documents, name='get-site-engineer-documents'),
    path('construction/all-documents/', views_construction.get_all_documents_for_accountant, name='get-all-documents'),
    
    # ============================================
    # ACCOUNTANT DOCUMENT MANAGEMENT ENDPOINTS
    # ============================================
    # Material Bills
    path('construction/upload-material-bill/', views_accountant_documents.upload_material_bill, name='upload-material-bill'),
    path('construction/material-bills/', views_accountant_documents.get_material_bills, name='get-material-bills'),
    
    # Vendor Bills
    path('construction/upload-vendor-bill/', views_accountant_documents.upload_vendor_bill, name='upload-vendor-bill'),
    path('construction/vendor-bills/', views_accountant_documents.get_vendor_bills, name='get-vendor-bills'),
    
    # Site Agreements
    path('construction/upload-site-agreement/', views_accountant_documents.upload_site_agreement, name='upload-site-agreement'),
    path('construction/site-agreements/', views_accountant_documents.get_site_agreements, name='get-site-agreements'),
    
    # Labor Mismatch Detection
    path('construction/labor-mismatches/', views_labor_mismatch.detect_labor_mismatches, name='detect-labor-mismatches'),
    
    # ============================================
    # MATERIAL INVENTORY MANAGEMENT ENDPOINTS
    # ============================================
    path('material/stock/', views_material.get_material_stock, name='get-material-stock'),
    path('material/balance/', views_material.get_material_balance, name='get-material-balance'),
    path('material/add-stock/', views_material.add_material_stock, name='add-material-stock'),
    path('material/record-usage/', views_material.record_material_usage, name='record-material-usage'),
    path('material/usage-history/', views_material.get_material_usage_history, name='get-material-usage-history'),
    path('material/low-stock-alerts/', views_material.get_low_stock_alerts, name='get-low-stock-alerts'),
    path('material/types/', views_material.get_material_types, name='get-material-types'),
    
    # Old Firebase endpoints (deprecated but kept for compatibility)
    path('auth/signin/', views.signin, name='signin'),
    path('user/profile/', views.get_profile, name='get-profile'),
    path('user/profile/update/', views.update_profile, name='update-profile'),
    
    # ============================================
    # BUDGET MANAGEMENT SYSTEM
    # ============================================
    # Budget Allocation
    path('budget/allocate/', views_budget_management.allocate_budget, name='allocate-budget'),
    path('budget/update/', views_budget_management.update_budget, name='update-budget'),
    path('budget/allocate-or-update/', views_budget_management.allocate_or_update_budget, name='allocate-or-update-budget'),
    path('budget/allocation/<str:site_id>/', views_budget_management.get_budget_allocation, name='get-budget-allocation'),
    
    # Labour Salary Rates
    path('budget/labour-rate/', views_budget_management.set_labour_rate, name='set-labour-rate'),
    path('budget/labour-rates/<str:site_id>/', views_budget_management.get_labour_rates, name='get-labour-rates'),
    path('budget/delete-labour-type/', views_budget_management.delete_labour_type, name='delete-labour-type'),
    
    # Local Labour Rates (Area-specific)
    path('budget/local-labour-rates/<str:area>/', views_budget_management.get_local_labour_rates, name='get-local-labour-rates'),
    path('budget/local-labour-rate/', views_budget_management.set_local_labour_rate, name='set-local-labour-rate'),
    
    # Budget Utilization
    path('budget/utilization/<str:site_id>/', views_budget_management.get_budget_utilization, name='get-budget-utilization'),
    path('budget/labour-costs/<str:site_id>/', views_budget_management.get_labour_cost_details, name='get-labour-cost-details'),
    
    # Material & Other Cost Entry
    path('budget/add-material-cost/', views_budget_management.add_material_cost, name='add-material-cost'),
    path('budget/add-other-cost/', views_budget_management.add_other_cost, name='add-other-cost'),
    
    # Phase Payment Management
    path('budget/record-phase-payment/', views_budget_management.record_phase_payment, name='record-phase-payment'),
    path('budget/update-phase-payment/', views_budget_management.update_phase_payment, name='update-phase-payment'),
    path('budget/phase-payments/<str:site_id>/', views_budget_management.get_phase_payments, name='get-phase-payments'),
    
    # ============================================
    # EXCEL EXPORT ENDPOINTS
    # ============================================
    path('export/labour-entries/<str:site_id>/', views_export.export_labour_entries, name='export-labour-entries'),
    path('export/material-entries/<str:site_id>/', views_export.export_material_entries, name='export-material-entries'),
    path('export/budget-utilization/<str:site_id>/', views_export.export_budget_utilization, name='export-budget-utilization'),
    path('export/bills/<str:site_id>/', views_export.export_bills, name='export-bills'),
    
    # Old CRUD endpoints (working)
    path('', include(router.urls)),
]
