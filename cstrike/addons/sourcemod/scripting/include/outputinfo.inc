#if defined _outputinfo_included
  #endinput
#endif
#define _outputinfo_included

/**
 * Gets the number of actions for given output
 * Note that this can change if an action has been deleted due to being used more than TimesToFire
 *
 * @param entity		Entity to use
 * @param output		The name of the output (e.g. m_OnTrigger)
 *
 * @return				Number of actions for that entity output
 */
native int GetOutputCount(int entity, const char[] output);

/**
 * Gets the name of the entity(s) to cause the action in
 * !activator = entity that activated output, !caller = entity that called output
 *
 * @param entity		Entity to use
 * @param output		The name of the output (e.g. m_OnTrigger)
 * @param index			The index of the action to use
 * @param target		Output string buffer

 * @return				True on success, false otherwise
 */
native bool GetOutputTarget(int entity, const char[] output, int index, char[] target);

/**
 * Gets the name of the action to fire
 *
 * @param entity		Entity to use
 * @param output		The name of the output (e.g. m_OnTrigger)
 * @param index			The index of the action to use
 * @param targetinput	Output string buffer
 * @param maxlen		Max length of output string buffer

 * @return				True on success, false otherwise
 */
native bool GetOutputTargetInput(int entity, const char[] output, int index, char[] targetinput);

/**
 * Gets the parameter to send, 0 if none
 *
 * @param entity		Entity to use
 * @param output		The name of the output (e.g. m_OnTrigger)
 * @param index			The index of the action to use
 * @param parameter		Output string buffer
 * @param maxlen		Max length of output string buffer

 * @return				True on success, false otherwise
 */
native bool GetOutputParameter(int entity, const char[] output, int index, char[] parameter);

/**
 * Gets the number of seconds to wait before firing the action
 *
 * @param entity		Entity to use
 * @param output		The name of the output (e.g. m_OnTrigger)
 * @param index			The index of the action to use

 * @return				Delay in seconds, or -1.0 on failure
 */
native float GetOutputDelay(int entity, const char[] output, int index);

/**
 * Do not edit below this line!
 */
public Extension __ext_outputinfo =
{
	name = "outputinfo",
	file = "outputinfo.ext",
#if defined AUTOLOAD_EXTENSIONS
	autoload = 1,
#else
	autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_EXTENSIONS
public __ext_outputinfo_SetNTVOptional()
{
	MarkNativeAsOptional("GetOutputCount");
	MarkNativeAsOptional("GetOutputTarget");
	MarkNativeAsOptional("GetOutputTargetInput");
	MarkNativeAsOptional("GetOutputParameter");
	MarkNativeAsOptional("GetOutputDelay");
}
#endif
