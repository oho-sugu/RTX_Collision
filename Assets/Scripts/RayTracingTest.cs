using UnityEngine;
using UnityEngine.Experimental.Rendering;

[ExecuteInEditMode]
public class RayTracingTest : MonoBehaviour
{     
    public RayTracingShader rayTracingShader = null;
    public Light pointLight = null;
    public Cubemap envMap = null;

    private int cameraWidth = 0;
    private int cameraHeight = 0;

    private RenderTexture rayTracingOutput = null;     

	private RayTracingAccelerationStructure raytracingAccelerationStructure = null;

    private void BuildRaytracingAccelerationStructure()
    {
        if (raytracingAccelerationStructure == null)
        {
            RayTracingAccelerationStructure.RASSettings settings = new RayTracingAccelerationStructure.RASSettings();
            settings.rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything;
            settings.managementMode = RayTracingAccelerationStructure.ManagementMode.Automatic;
            settings.layerMask = 255;

            raytracingAccelerationStructure = new RayTracingAccelerationStructure(settings);

            raytracingAccelerationStructure.Build();
        }
    }

    private void ReleaseResources()
    {
        if (raytracingAccelerationStructure != null)
        {
            raytracingAccelerationStructure.Release();
            raytracingAccelerationStructure = null;
        }

        if (rayTracingOutput)
        {
            rayTracingOutput.Release();
            rayTracingOutput = null;
        }

        cameraWidth = 0;
        cameraHeight = 0;
    }

    private void CreateResources()
    {
        BuildRaytracingAccelerationStructure();

        if (cameraWidth != Camera.main.pixelWidth || cameraHeight != Camera.main.pixelHeight)
        {
            if (rayTracingOutput)
                rayTracingOutput.Release();

            rayTracingOutput = new RenderTexture(Camera.main.pixelWidth, Camera.main.pixelHeight, 0, RenderTextureFormat.ARGBHalf);
            rayTracingOutput.enableRandomWrite = true;
            rayTracingOutput.Create();
          
            cameraWidth = Camera.main.pixelWidth;
            cameraHeight = Camera.main.pixelHeight;
        }
    }

    void OnDisable()
    {
        ReleaseResources();
    }

    public void Start()
    {        
    }

    private void Update()
    {
        CreateResources();
    }

    void OnRenderImage(RenderTexture src, RenderTexture dest)
    {
        if (!SystemInfo.supportsRayTracing || !rayTracingShader)
        {
            Debug.Log("The RayTracing API is not supported by this GPU or by the current graphics API.");
            Graphics.Blit(src, dest);
            return;
        }
   
        if (pointLight == null || pointLight.type != LightType.Point)
        {
            Debug.Log("Please set a point light to this script.");
            return;
        }

        if (raytracingAccelerationStructure == null)
            return;

        // Use Shader Pass "Test" in surface (material) shaders."
        rayTracingShader.SetShaderPass("Test");

        Shader.SetGlobalVector(Shader.PropertyToID("PointLightPosition"), pointLight.transform.position);
        Shader.SetGlobalVector(Shader.PropertyToID("PointLightColor"), pointLight.color);
        Shader.SetGlobalFloat(Shader.PropertyToID("PointLightRange"), pointLight.range);
        Shader.SetGlobalFloat(Shader.PropertyToID("PointLightIntensity"), pointLight.intensity);
        Shader.SetGlobalMatrix(Shader.PropertyToID("g_InvViewMatrix"), Camera.main.cameraToWorldMatrix);
        Shader.SetGlobalTexture(Shader.PropertyToID("g_EnvTex"), envMap);
        
        raytracingAccelerationStructure.Build();

        // Input
        rayTracingShader.SetAccelerationStructure(Shader.PropertyToID("g_SceneAccelStruct"), raytracingAccelerationStructure);
        rayTracingShader.SetMatrix(Shader.PropertyToID("g_InvViewMatrix"), Camera.main.cameraToWorldMatrix);
        rayTracingShader.SetFloat(Shader.PropertyToID("g_Zoom"), Mathf.Tan(Mathf.Deg2Rad * Camera.main.fieldOfView * 0.5f));
   
        // Output
        rayTracingShader.SetTexture("g_Output", rayTracingOutput);

        rayTracingShader.Dispatch("MainRayGenShader", cameraWidth, cameraHeight, 1);

        Graphics.Blit(rayTracingOutput, dest);
    }
}
