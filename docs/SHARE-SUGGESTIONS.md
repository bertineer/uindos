# Share app suggestions

Windows 11 can show suggested apps in Share surfaces. On the target Windows 11
Pro VM (26H2, build 26300.9711), the observed starting value was **On**.

To turn this current-user preference off, open **Settings > System > Share**
and switch **Show me suggested apps in share surfaces** to **Off**. This hides
optional app suggestions in Share surfaces. It does not remove the Share
interface or apps, and it is not an all-user default or a guarantee against
apps being installed or suggested elsewhere.

The feature is described for people signed in with a work or school account.
Without that account context, there may be no relevant app suggestions to
observe. The preference makes no guarantee about RAM use or network traffic.

To restore the observed prior value, return to the same Settings page and set
the toggle to **On**, but only if the user has not changed it since this
setting was applied. On build 26300.9711, native On-to-Off application, an
unchanged repeat, restoration to On, final Off and reopened-page verification
passed. These establish the saved preference, with account-dependent Share
content and later reboot/update persistence still unverified.
